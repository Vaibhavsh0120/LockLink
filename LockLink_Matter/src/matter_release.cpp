#include "matter_release.h"

#include <Matter.h>
#include <MatterEndpoints/MatterOnOffPlugin.h>
#include <Preferences.h>
#include <atomic>
#include <app/CommandHandlerInterface.h>
#include <app/CommandHandlerInterfaceRegistry.h>
#include <bootloader_random.h>
#include <esp_random.h>
#include <platform/DeviceInstanceInfoProvider.h>
#include "config.h"

namespace {
using namespace chip::app::Clusters;
MatterOnOffPlugin releaseSwitch;
ReleaseOutput* output = nullptr;
bool armed = false;
bool acceptingCommands = false;  // Accessed only on the Matter task.
bool reporting = false;          // Suppress actuator callbacks on state reports.
bool started = false;
std::atomic<bool> syncPending{false};
std::atomic<bool> resetting{false};
uint32_t lastSync = 0;

// The SDK exposes startup failure detection to derived implementations.
struct Lifecycle : ArduinoMatter {
  static bool ready() { return isStackStarted(); }
};

bool configurePairing() {
  Preferences prefs;
  if (!prefs.begin("locklink-matter", false)) return false;
  uint32_t passcode = prefs.getUInt("passcode", 0);
  uint16_t discriminator = prefs.getUShort("discriminator", 0xffff);
  if (passcode == 0 || discriminator > 4095) {
    // The radios have not started yet. Enable the ESP32-S3 hardware entropy
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
  if (acceptingCommands && releaseSwitch.getOnOff() == active) {
    return true;
  }
  esp_matter_attr_val_t value = esp_matter_bool(active);
  reporting = true;
  const esp_err_t result = esp_matter::attribute::update(
      releaseSwitch.getEndPointId(), OnOff::Id, OnOff::Attributes::OnOff::Id, &value);
  reporting = false;
  if (result == ESP_OK) acceptingCommands = true;
  return result == ESP_OK;
}

void syncState(intptr_t) {
  reportState();
  syncPending = false;
}

// Intercept commands before the SDK's OnOff server, which ignores an On/Off
// matching its cached attribute. That cache can lag HTTP releases/timer expiry.
// HandleCommand decodes the generated command payload before touching output.
class ReleaseCommands : public chip::app::CommandHandlerInterface {
 public:
  explicit ReleaseCommands(chip::EndpointId endpoint)
      : CommandHandlerInterface(chip::MakeOptional(endpoint), OnOff::Id) {}

  void InvokeCommand(HandlerContext& context) override {
    HandleCommand<OnOff::Commands::On::DecodableType>(context,
        [](HandlerContext& ctx, const auto&) { execute(ctx, Action::on); });
    HandleCommand<OnOff::Commands::Off::DecodableType>(context,
        [](HandlerContext& ctx, const auto&) { execute(ctx, Action::off); });
    HandleCommand<OnOff::Commands::Toggle::DecodableType>(context,
        [](HandlerContext& ctx, const auto&) { execute(ctx, Action::toggle); });
    if (!context.mCommandHandled) {
      context.SetCommandHandled();
      context.mCommandHandler.AddStatus(context.mRequestPath,
          chip::Protocols::InteractionModel::Status::UnsupportedCommand);
    }
  }

 private:
  enum class Action { on, off, toggle };
  static void execute(HandlerContext& context, Action action) {
    using Status = chip::Protocols::InteractionModel::Status;
    Status status = Status::Failure;
    if (acceptingCommands && armed && !resetting) {
      // Toggle follows actual release activity, never the lagging attribute.
      const bool turnOn = action == Action::on ||
          (action == Action::toggle && !output->active());
      if (turnOn) {
        const auto result = output->release();
        // Repeated On succeeds without restarting the two-second cutoff.
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
bool begin(ReleaseOutput& relay, bool isArmed) {
  output = &relay;
  armed = isArmed;
  if (!Matter.selectNetwork(MATTER_NETWORK_WIFI) || !configurePairing() ||
      !releaseSwitch.begin(false)) return false;
  if (!Matter.setVendorName("LockLink") ||
      !Matter.setProductName("LockLink Door Release") ||
      !Matter.setDeviceName(matter_config::deviceName)) return false;
  releaseSwitch.onChange([](bool) {
    // Only validated commands actuate. Startup restoration, scene attribute
    // writes, and reporting itself must never initiate a release.
    return reporting;
  });
  releaseSwitch.onIdentify([](bool) {
    // Identification must never actuate the door.
    return true;
  });
  static ReleaseCommands commands(releaseSwitch.getEndPointId());
  if (chip::app::CommandHandlerInterfaceRegistry::Instance()
          .RegisterCommandHandler(&commands) != CHIP_NO_ERROR) return false;
  Matter.begin();
  started = Lifecycle::ready();
  if (!started) return false;
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
  Serial.println("Accessory: Door Release (momentary switch / outlet)");
  Serial.println("ON releases for 2 seconds; OFF ends release. No door-position sensor.");
  if (!Matter.isDeviceCommissioned()) {
    Serial.println("Keep this one-time setup code private:");
    Serial.println(Matter.getManualPairingCode());
    // The SDK supplies a URL; prefer manual entry so no website is needed.
    Serial.println("Optional setup QR URL (contains pairing credentials):");
    Serial.println(Matter.getOnboardingQRCodeUrl());
  } else {
    Serial.println("Already paired. Use the paired ecosystem's sharing/pairing mode");
    Serial.println("to obtain a fresh code for an additional ecosystem.");
  }
}

void resetPairing() {
  if (!started) return;
  resetting = true;
  output->shutdown();
  output->updateIndicator();
  Serial.println("Resetting Matter pairing and Wi-Fi. App key is unchanged.");
  Matter.decommission();
}
}
