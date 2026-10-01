#include "matter_release.h"

#include <Matter.h>
#include <MatterEndPoint.h>
#include <Preferences.h>
#include <atomic>
#include <app/CommandHandlerInterface.h>
#include <app/CommandHandlerInterfaceRegistry.h>
#include <app/server/Server.h>
#include <app/clusters/door-lock-server/door-lock-server.h>
#include <platform/ESP32/NetworkCommissioningDriver.h>
#include <bootloader_random.h>
#include <esp_random.h>
#include <platform/DeviceInstanceInfoProvider.h>
#include <setup_payload/OnboardingCodesUtil.h>
#include <setup_payload/QRCodeSetupPayloadGenerator.h>
#include <setup_payload/ManualSetupPayloadGenerator.h>
#include <lib/support/utf8.h>
#include "config.h"
#include "device_console.h"
#include "local_network.h"

// Arduino's Matter package leaves this hook to sketches that create a Door
// Lock endpoint directly. Initialize the cluster's server for that endpoint.
void emberAfDoorLockClusterInitCallback(chip::EndpointId endpoint) {
  DoorLockServer::Instance().InitEndpoint(endpoint);
}

namespace {
using namespace chip::app::Clusters;
struct ReleaseLock : MatterEndPoint {
  bool attributeChangeCB(uint16_t, uint32_t, uint32_t,
                         esp_matter_attr_val_t*) override {
    // LockState is reported from the relay, never used to actuate it.
    return true;
  }
};
ReleaseLock releaseLock;
ReleaseOutput* output = nullptr;
bool armed = false;
bool acceptingCommands = false;  // Accessed only on the Matter task.
bool started = false;
bool reportedActive = false;
std::atomic<bool> syncPending{false};
std::atomic<bool> resetting{false};
uint32_t lastSync = 0;
bool additionalWindow = false;
uint32_t additionalDeadline = 0;
String additionalHomes;
String additionalWindowId;
String additionalCode;
String additionalQr;

String homeId(const chip::FabricInfo& fabric) {
  char id[17];
  snprintf(id, sizeof(id), "%016llx", static_cast<unsigned long long>(fabric.GetCompressedFabricId()));
  return id;
}

String homeIds() {
  String ids;
  auto& table = chip::Server::GetInstance().GetFabricTable();
  const auto pending = table.GetPendingNewFabricIndex();
  for (const auto& fabric : table) {
    if (fabric.GetFabricIndex() != pending) ids += homeId(fabric);
  }
  return ids;
}

bool ownsWindow() {
  auto& window = chip::Server::GetInstance().GetCommissioningWindowManager();
  if (!window.IsCommissioningWindowOpen() ||
      int32_t(millis() - additionalDeadline) >= 0 || homeIds() != additionalHomes) {
    additionalWindow = false;
    additionalCode = "";
    additionalQr = "";
  }
  return additionalWindow;
}

void seedConfiguredWiFi(intptr_t) {
  // Called once under the CHIP lock after driver initialization. Never take
  // over a commissioned device, a saved network, or an in-progress pairing.
  if (resetting || config::wifiSsid[0] == '\0' || Matter.isDeviceCommissioned() ||
      chip::Server::GetInstance().GetFailSafeContext().IsFailSafeArmed()) return;
  wifi_config_t saved = {};
  if (esp_wifi_get_config(WIFI_IF_STA, &saved) != ESP_OK) {
    console.println("Wi-Fi setup: cannot read saved network; leaving it unchanged.");
    return;
  }
  if (saved.sta.ssid[0] != '\0') {
    console.println("Wi-Fi setup: keeping the saved network.");
    return;
  }
  using namespace chip::DeviceLayer::NetworkCommissioning;
  auto& driver = ESPWiFiDriver::GetInstance();
  auto* networks = driver.GetNetworks();
  if (!networks) return;
  const bool hasNetwork = networks->Count() != 0;
  networks->Release();
  if (hasNetwork) return;
  chip::MutableCharSpan debugText;
  uint8_t index = 0;
  const chip::ByteSpan ssid(reinterpret_cast<const uint8_t*>(config::wifiSsid),
                            sizeof(config::wifiSsid) - 1);
  const chip::ByteSpan password(reinterpret_cast<const uint8_t*>(config::wifiPassword),
                                sizeof(config::wifiPassword) - 1);
  if (driver.AddOrUpdateNetwork(ssid, password, debugText, index) != Status::kSuccess) {
    console.println("Wi-Fi setup: configured network rejected; Home pairing remains available.");
    return;
  }
  // Use the same driver as Matter commissioning, not Arduino WiFi.begin or
  // another reconnect loop. This enables CHIP's normal station reconnects.
  auto err = driver.ConnectWiFiNetwork(config::wifiSsid, ssid.size(),
                                      config::wifiPassword, password.size());
  if (err == CHIP_NO_ERROR) err = driver.CommitConfiguration();
  if (err != CHIP_NO_ERROR) {
    driver.RevertConfiguration();
    console.println("Wi-Fi setup failed; Home pairing remains available.");
    return;
  }
  console.println("Wi-Fi setup: configured network saved; connection pending. Use STATUS to check.");
}

// The SDK exposes startup failure detection to derived implementations.
struct Lifecycle : ArduinoMatter {
  static void prepare() { _init(); }
  static bool ready() { return isStackStarted(); }
};

bool configurePairing() {
  Preferences prefs;
  if (!prefs.begin("locklink-matter", false)) return false;
  uint32_t passcode = prefs.getUInt("passcode", 0);
  uint16_t discriminator = prefs.getUShort("discriminator", 0xffff);
  if (passcode == 0 || discriminator > 4095) {
    // The radios have not started yet. Enable the ESP32-C3 hardware entropy
    // source while generating the per-device commissioning credentials.
    bootloader_random_enable();
    do {
      passcode = 1 + esp_random() % 99999998;
    } while (!Matter.setSetupPasscode(passcode));
    discriminator = esp_random() & 0x0fff;
    bootloader_random_disable();
    if (prefs.putUInt("passcode", passcode) != sizeof(passcode) ||
        prefs.putUShort("discriminator", discriminator) != sizeof(discriminator)) {
      prefs.end();
      return false;
    }
  }
  prefs.end();
  return Matter.setSetupPasscode(passcode) &&
         Matter.setSetupDiscriminator(discriminator);
}

bool reportState() {
  // ScheduleWork runs under the Matter stack's lock. Capture current output
  // here, not when scheduling, so an old queued report cannot overwrite a
  // newer command. Publishing state must never initiate another pulse.
  const bool active = output->active();
  if (acceptingCommands && reportedActive == active) {
    return true;
  }
  const auto state = active ? DoorLock::DlLockState::kUnlocked
                            : DoorLock::DlLockState::kLocked;
  if (!DoorLockServer::Instance().SetLockState(releaseLock.getEndPointId(), state))
    return false;
  reportedActive = active;
  acceptingCommands = true;
  return true;
}

void syncState(intptr_t) {
  reportState();
  syncPending = false;
}

// Intercept lock commands so a controller command acts on the relay, not on
// the server's cached state. That cache can lag HTTP releases/timer expiry.
// HandleCommand decodes the generated command payload before touching output.
class ReleaseCommands : public chip::app::CommandHandlerInterface {
 public:
  explicit ReleaseCommands(chip::EndpointId endpoint)
      : CommandHandlerInterface(chip::MakeOptional(endpoint), DoorLock::Id) {}

  void InvokeCommand(HandlerContext& context) override {
    HandleCommand<DoorLock::Commands::UnlockDoor::DecodableType>(context,
        [](HandlerContext& ctx, const auto&) { execute(ctx, true); });
    HandleCommand<DoorLock::Commands::LockDoor::DecodableType>(context,
        [](HandlerContext& ctx, const auto&) { execute(ctx, false); });
    if (!context.mCommandHandled) {
      context.SetCommandHandled();
      context.mCommandHandler.AddStatus(context.mRequestPath,
          chip::Protocols::InteractionModel::Status::UnsupportedCommand);
    }
  }

 private:
  static void execute(HandlerContext& context, bool unlock) {
    using Status = chip::Protocols::InteractionModel::Status;
    Status status = Status::Failure;
    if (acceptingCommands && armed && !resetting) {
      if (unlock) {
        const auto result = output->release();
        // Repeated Unlock succeeds without restarting the one-second cutoff.
        if (result == ReleaseOutput::Result::started ||
            result == ReleaseOutput::Result::busy) status = Status::Success;
      } else {
        output->stop();
        status = Status::Success;
      }
      // Reporting is separate from actuation. A reporting failure is retried
      // by poll(); it must not replay a completed command or restart a pulse.
      reportState();
    }
    context.mCommandHandler.AddStatus(context.mRequestPath, status);
  }
};
}

namespace matter_release {
HomesSnapshot homesSnapshot() {
  HomesSnapshot result;
  result.capacity = CHIP_CONFIG_MAX_FABRICS;
  if (!started) return result;
  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  auto& table = chip::Server::GetInstance().GetFabricTable();
  result.commissioned = false;
  result.windowOpen = chip::Server::GetInstance().GetCommissioningWindowManager().IsCommissioningWindowOpen();
  result.additional = ownsWindow();
  if (result.additional) result.windowId = additionalWindowId;
  result.json = "[";
  const auto pending = table.GetPendingNewFabricIndex();
  for (const auto& fabric : table) {
    // AddNOC creates a provisional entry which can still be rolled back.
    // Only CommissioningComplete commits a new home for pairing checks.
    if (fabric.GetFabricIndex() == pending) continue;
    result.commissioned = true;
    if (result.json.length() > 1) result.json += ',';
    auto label = fabric.GetFabricLabel();
    String name;
    for (size_t i = 0; i < label.size(); ++i) name += label.data()[i];
    result.description += homeId(fabric) + "  " + (name.isEmpty() ?
        String("Home ") + fabric.GetFabricIndex() : name) + "\n";
    result.json += String("{\"id\":") + jsonQuote(homeId(fabric)) +
        ",\"index\":" + fabric.GetFabricIndex() + ",\"vendor_id\":" +
        fabric.GetVendorId() + ",\"label\":" + jsonQuote(name) + '}';
  }
  result.json += ']';
  return result;
}

String prepareAdditionalPairing(String& message, String& qrPayload) {
  qrPayload = "";
  if (!started) { message = "Matter unavailable. Restart the device."; return ""; }
  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  auto& server = chip::Server::GetInstance();
  auto& table = server.GetFabricTable();
  auto& window = server.GetCommissioningWindowManager();
  if (table.FabricCount() == 0) { message = "Use PAIR for the first home."; return ""; }
  if (table.FabricCount() >= CHIP_CONFIG_MAX_FABRICS) {
    message = "Connected homes are full. Remove an unused home first."; return "";
  }
  if (!server.GetFailSafeContext().IsFailSafeFullyDisarmed() ||
      (window.IsCommissioningWindowOpen() && !ownsWindow())) {
    message = "Pairing is already in progress. Finish it or wait for its window to close."; return "";
  }
  // Two phones may request setup together. Reuse the live temporary window's
  // credentials rather than silently replacing a code another phone is using.
  if (ownsWindow()) {
    qrPayload = additionalQr;
    message = String("Code: ") + additionalCode + "\nPairing is open. This code expires with the current window.";
    return additionalCode;
  }
  additionalWindow = false;
  chip::SetupPayload payload;
  uint8_t salt[16];
  chip::Crypto::Spake2pVerifier verifier;
  if (chip::SetupPayload::generateRandomSetupPin(payload.setUpPINCode) != CHIP_NO_ERROR ||
      chip::Crypto::DRBG_get_bytes(salt, sizeof(salt)) != CHIP_NO_ERROR ||
      verifier.Generate(1000, chip::ByteSpan(salt), payload.setUpPINCode) != CHIP_NO_ERROR) {
    message = "Could not create a setup code. Try again."; return "";
  }
  payload.discriminator.SetLongValue(esp_random() & 0x0fff);
  payload.rendezvousInformation.SetValue(chip::RendezvousInformationFlags(chip::RendezvousInformationFlag::kOnNetwork));
  auto* info = chip::DeviceLayer::GetDeviceInstanceInfoProvider();
  info->GetVendorId(payload.vendorID);
  info->GetProductId(payload.productID);
  std::string manual, qr;
  if (chip::ManualSetupPayloadGenerator(payload).payloadDecimalStringRepresentation(manual) != CHIP_NO_ERROR ||
      chip::QRCodeSetupPayloadGenerator(payload).payloadBase38Representation(qr) != CHIP_NO_ERROR) {
    message = "Could not create a setup code. Try again."; return "";
  }
  const auto& opener = *table.begin();
  if (window.OpenEnhancedCommissioningWindow(chip::System::Clock::Seconds32(300),
      payload.discriminator.GetLongValue(), verifier, 1000, chip::ByteSpan(salt),
      opener.GetFabricIndex(), opener.GetVendorId()) != CHIP_NO_ERROR) {
    message = "Pairing unavailable. Wait, then try again."; return "";
  }
  additionalWindow = true;
  char windowId[17];
  snprintf(windowId, sizeof(windowId), "%08lx%08lx", static_cast<unsigned long>(esp_random()),
           static_cast<unsigned long>(esp_random()));
  additionalWindowId = windowId;
  additionalDeadline = millis() + 300000;
  additionalHomes = homeIds();
  additionalCode = manual.c_str();
  additionalQr = qr.c_str();
  qrPayload = qr.c_str();
  message = String("Code: ") + manual.c_str() + "\nPairing open for 5 minutes. Use the same Wi-Fi.";
  return String(manual.c_str());
}

bool closePairing(String& message) {
  if (!started) { message = "Matter unavailable."; return false; }
  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  if (!chip::Server::GetInstance().GetFailSafeContext().IsFailSafeFullyDisarmed()) {
    message = "Pairing is in progress. Wait for it to finish."; return false;
  }
  if (!ownsWindow()) { message = "No LockLink pairing window is open."; return false; }
  chip::Server::GetInstance().GetCommissioningWindowManager().CloseCommissioningWindow();
  additionalWindow = false;
  additionalCode = "";
  additionalQr = "";
  message = "Pairing window closed.";
  return true;
}

bool manageHome(const String& id, const String& hexLabel, bool remove, String& message) {
  if (!started) { message = "Matter unavailable."; return false; }
  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  auto& server = chip::Server::GetInstance();
  if (!server.GetFailSafeContext().IsFailSafeFullyDisarmed() ||
      server.GetCommissioningWindowManager().IsCommissioningWindowOpen()) {
    message = "Close pairing or wait for it to finish before changing homes."; return false;
  }
  String name;
  if (!remove) {
    if (hexLabel.isEmpty() || hexLabel.length() > 64 || hexLabel.length() % 2) {
      message = "Use a name of 1 to 32 UTF-8 bytes."; return false;
    }
    for (unsigned i = 0; i < hexLabel.length(); i += 2) {
      if (!isHexadecimalDigit(hexLabel[i]) || !isHexadecimalDigit(hexLabel[i + 1])) {
        message = "Invalid name."; return false;
      }
      const char value = strtoul(hexLabel.substring(i, i + 2).c_str(), nullptr, 16);
      if (static_cast<uint8_t>(value) < 32 || value == 127) { message = "Invalid name."; return false; }
      name += value;
    }
    if (!chip::Utf8::IsValid(chip::CharSpan(name.c_str(), name.length()))) {
      message = "Invalid UTF-8 name."; return false;
    }
  }
  auto& table = server.GetFabricTable();
  chip::FabricIndex index = chip::kUndefinedFabricIndex;
  for (const auto& fabric : table) {
    if (homeId(fabric).equalsIgnoreCase(id)) index = fabric.GetFabricIndex();
    else if (!remove) {
      const auto label = fabric.GetFabricLabel();
      if (label.size() == name.length() && memcmp(label.data(), name.c_str(), label.size()) == 0) {
        message = "Another home already uses that name."; return false;
      }
    }
  }
  if (id.length() != 16 || index == chip::kUndefinedFabricIndex) {
    message = "Home no longer found. Refresh the list."; return false;
  }
  if (remove) output->stop();
  const auto error = remove ? table.Delete(index) :
      table.SetFabricLabel(index, chip::CharSpan(name.c_str(), name.length()));
  if (error != CHIP_NO_ERROR) { message = "Change failed. Refresh before trying again."; return false; }
  message = remove ? "Home removed. Wi-Fi and other homes are kept." : "Home renamed.";
  return true;
}

bool commissioned() {
  if (!started) return false;
  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  return !homeIds().isEmpty();
}

String identity() {
  uint16_t vendor = 0, product = 0;
  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  auto* info = chip::DeviceLayer::GetDeviceInstanceInfoProvider();
  info->GetVendorId(vendor);
  info->GetProductId(product);
  char text[48];
  snprintf(text, sizeof(text), "Test VID: 0x%04X; PID: 0x%04X", vendor, product);
  return text;
}

String preparePairing(String& message, String& qrPayload) {
  qrPayload = "";
  if (!started) { message = "Matter unavailable. Restart the device."; return ""; }
  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  if (!chip::Server::GetInstance().GetFailSafeContext().IsFailSafeFullyDisarmed()) {
    message = "Pairing is in progress. Wait for it to finish.";
    return "";
  }
  if (Matter.isDeviceCommissioned()) {
    message = "Already paired. Use PAIR ADD or get a sharing code from the connected home app.";
    return "";
  }
  auto& window = chip::Server::GetInstance().GetCommissioningWindowManager();
  // USB PAIR must still work without Wi-Fi after the initial window expires.
  // Match the onboarding payload and ArduinoMatter's supported transports.
  const auto advertisement = Matter.isBLECommissioningEnabled()
      ? chip::CommissioningWindowAdvertisement::kAllSupported
      : chip::CommissioningWindowAdvertisement::kDnssdOnly;
  if (!window.IsCommissioningWindowOpen() &&
      window.OpenBasicCommissioningWindow(chip::System::Clock::Seconds16(300),
          advertisement) != CHIP_NO_ERROR) {
    message = "Pairing unavailable. Wait, then try PAIR again.";
    return "";
  }
  const String code = Matter.getManualPairingCode();
  // Match ArduinoMatter's onboarding flags and use its live credential provider.
  // Return raw MT: data only to this caller, never to shared serial history.
  chip::RendezvousInformationFlags flags(chip::RendezvousInformationFlag::kOnNetwork);
  if (Matter.isBLECommissioningEnabled()) flags.Set(chip::RendezvousInformationFlag::kBLE);
  char buffer[chip::QRCodeBasicSetupPayloadGenerator::kMaxQRCodeBase38RepresentationLength + 1] = {};
  chip::MutableCharSpan qr(buffer, sizeof(buffer));
  if (!code.isEmpty() && GetQRCode(qr, flags) == CHIP_NO_ERROR) qrPayload = buffer;
  message = String("Code: ") + code + "\nPairing open. Add Door Release in your home app.";
  return code;
}

bool begin(ReleaseOutput& relay, bool isArmed) {
  output = &relay;
  armed = isArmed;
  if (!Matter.selectNetwork(MATTER_NETWORK_WIFI) || !configurePairing()) return false;
  // ArduinoMatter otherwise permanently releases BLE RAM after commissioning.
  // Keep it available so removing the last home can be followed by BLE setup
  // without restarting; advertising remains controlled by pairing windows.
  if (Matter.isBLECommissioningEnabled() &&
      !Matter.setBLEMemoryReleaseEnabled(false)) return false;
  Lifecycle::prepare();
  esp_matter::endpoint::door_lock::config_t lockConfig;
  lockConfig.door_lock.lock_state =
      static_cast<uint8_t>(DoorLock::DlLockState::kLocked);
  lockConfig.door_lock.lock_type =
      static_cast<uint8_t>(DoorLock::DlLockType::kOther);
  lockConfig.door_lock.actuator_enabled = true;
  auto* endpoint = esp_matter::endpoint::door_lock::create(
      esp_matter::node::get(), &lockConfig, ENDPOINT_FLAG_NONE, &releaseLock);
  if (!endpoint) return false;
  releaseLock.setEndPointId(esp_matter::endpoint::get_id(endpoint));
  if (!Matter.setVendorName("LockLink") ||
      !Matter.setProductName("LockLink Door Release") ||
      !Matter.setDeviceName(matter_config::deviceName)) return false;
  releaseLock.onIdentify([](bool) {
    // Identification must never actuate the door.
    return true;
  });
  static ReleaseCommands commands(releaseLock.getEndPointId());
  if (chip::app::CommandHandlerInterfaceRegistry::Instance()
          .RegisterCommandHandler(&commands) != CHIP_NO_ERROR) return false;
  Matter.onEvent([](matterEvent_t event, const chip::DeviceLayer::ChipDeviceEvent*) {
    if (event == MATTER_COMMISSIONING_WINDOW_CLOSED || event == MATTER_COMMISSIONING_COMPLETE) {
      additionalWindow = false;
      additionalCode = "";
      additionalQr = "";
    }
  });
  // Configure only driver allocation limits. Matter still creates interfaces,
  // starts Wi-Fi, restores credentials and handles station reconnection.
  if (!local_network::prepareBuffers()) {
    console.println("Wi-Fi memory configuration failed. Restart the device.");
    return false;
  }
  Matter.begin();
  started = Lifecycle::ready();
  if (!started) return false;
  if (config::wifiSsid[0] != '\0' &&
      chip::DeviceLayer::PlatformMgr().ScheduleWork(seedConfiguredWiFi, 0) != CHIP_NO_ERROR) {
    console.println("Wi-Fi setup could not be scheduled; Home pairing remains available.");
  }
  printPairing();
  return true;
}

void poll() {
  if (!started || uint32_t(millis() - lastSync) < 100) return;
  lastSync = millis();
  // A bounded queue: at most one report may be pending at any time.
  if (syncPending.exchange(true)) return;
  if (chip::DeviceLayer::PlatformMgr().ScheduleWork(syncState, 0) != CHIP_NO_ERROR) {
    syncPending = false;
  }
}

void printPairing() {
  uint16_t vendor = 0, product = 0;
  auto* info = chip::DeviceLayer::GetDeviceInstanceInfoProvider();
  info->GetVendorId(vendor);
  info->GetProductId(product);
  Serial.printf("Matter test VID: 0x%04X, PID: 0x%04X\n", vendor, product);
  Serial.println("Accessory: Door Release (Matter door lock)");
  Serial.println("Unlock releases for 1 second; Lock ends release. No door-position sensor.");
  if (!Matter.isDeviceCommissioned()) {
    Serial.println("Keep this one-time setup code private:");
    Serial.println(Matter.getManualPairingCode());
    // The SDK supplies a URL; prefer manual entry so no website is needed.
    Serial.println("Optional setup QR URL (contains pairing credentials):");
    Serial.println(Matter.getOnboardingQRCodeUrl());
  } else {
    Serial.println("Already paired. Run PAIR ADD or use your home app's sharing mode");
    Serial.println("to obtain a fresh code for an additional home.");
  }
}

void printStatus() {
  console.printf("Matter: %s; Wi-Fi: %s\n",
      Matter.isDeviceCommissioned() ? "paired" : "not paired - add Door Release in Home",
      Matter.isWiFiConnected() ? "connected" : "not connected");
}

void resetPairing() {
  if (!started) return;
  resetting = true;
  output->shutdown();
  console.println("Resetting Matter pairing and Wi-Fi. App key is unchanged.");
  Matter.decommission();
}
}
