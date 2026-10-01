#include "terminal_commands.h"
#include "config.h"
#include "local_network.h"
#include "matter_release.h"
#include "memory_diagnostics.h"
#include <IPAddress.h>
#include <esp_system.h>
#include <esp_wifi.h>

TerminalReply terminalCommand(String command, ReleaseOutput& output, UnlockAuth& auth) {
  TerminalReply reply;
  command.trim();
  command.toUpperCase();
  reply.commissioned = matter_release::commissioned();
  if (command.isEmpty() || command == "HOMES") {
    // Read-only refresh; shared state is added to every reply below.
  }
  else if (command == "HELP") {
    reply.output = "HELP   Commands\nSTATUS Device state\nHOMES  Connected homes\nPAIR   First home setup code\nPAIR ADD   Add another home\nPAIR CLOSE   Close LockLink pairing\nHOME REMOVE <id>   Remove one home\nHOME NAME <id> <UTF-8 hex>   Rename home\nRESET MATTER   USB only; erases homes and Wi-Fi.";
  } else if (command == "STATUS") {
    const auto memory = memory_diagnostics::snapshot();
    const auto network = local_network::snapshot();
    wifi_ap_record_t accessPoint = {};
    const bool associated = esp_wifi_sta_get_ap_info(&accessPoint) == ESP_OK;
    wifi_ps_type_t powerSave = WIFI_PS_NONE;
    const bool powerSaveKnown = esp_wifi_get_ps(&powerSave) == ESP_OK;
    reply.output = String("LockLink v") + config::version + "\nWi-Fi: " + (network.ready() ? IPAddress(network.ipv4).toString() : "offline") +
        "\nWi-Fi link: " + (associated ? "connected" : "disconnected") +
        "\nSignal: " + (associated ? String(accessPoint.rssi) + " dBm" : "unavailable") +
        "\nModem sleep: " + (!powerSaveKnown ? "unknown" : powerSave == WIFI_PS_NONE ? "off" : "on") +
        "\nUptime: " + String(millis() / 1000) + " s; free heap: " + String(memory.free) + " bytes" +
        "\nHeap minimum: " + String(memory.minimum) + " bytes; largest block: " + String(memory.largest) + " bytes" +
        "\nAllocation failures: " + String(memory.allocationFailures) + "; last request: " + String(memory.lastFailedBytes) + " bytes" +
        "\nReset reason: " + String(static_cast<int>(esp_reset_reason())) +
        "\nMatter: " + (reply.commissioned ? "paired" : "not paired") +
        "\nOutput: " + (config::relayEnabled ? "relay" : "LED") +
        "; armed: " + (!config::relayEnabled || auth.ready() ? "yes" : "no") +
        "\nRelease: " + (output.active() ? "active" : "inactive") +
        "\n" + matter_release::identity();
  } else if (command == "PAIR") {
    reply.pairingCode = matter_release::preparePairing(reply.output, reply.pairingQrPayload);
    // Commissioning may have completed while the request acquired the stack lock.
    reply.commissioned = matter_release::commissioned();
    if (reply.commissioned) {
      reply.pairingCode = "";
      reply.pairingQrPayload = "";
      reply.output = "Already paired. Get a sharing code from the connected home app.";
    }
    reply.ok = reply.commissioned || !reply.pairingCode.isEmpty();
  } else if (command == "PAIR ADD") {
    reply.pairingCode = matter_release::prepareAdditionalPairing(reply.output, reply.pairingQrPayload);
    reply.ok = !reply.pairingCode.isEmpty();
  } else if (command == "PAIR CLOSE") {
    reply.ok = matter_release::closePairing(reply.output);
  } else if (command.startsWith("HOME REMOVE ")) {
    reply.ok = matter_release::manageHome(command.substring(12), "", true, reply.output);
  } else if (command.startsWith("HOME NAME ")) {
    const int separator = command.indexOf(' ', 10);
    reply.ok = separator > 10 && matter_release::manageHome(
        command.substring(10, separator), command.substring(separator + 1), false, reply.output);
    if (separator <= 10) reply.output = "Use HOME NAME <id> <UTF-8 hex>.";
  } else {
    reply.ok = false;
    reply.output = command == "RESET MATTER"
        ? "USB only. Erases homes and Wi-Fi."
        : "Unknown command. Type HELP.";
  }
  const auto homes = matter_release::homesSnapshot();
  reply.commissioned = homes.commissioned;
  reply.homesJson = homes.json;
  reply.fabricCapacity = homes.capacity;
  reply.pairingWindowOpen = homes.windowOpen;
  reply.additionalPairing = homes.additional;
  reply.pairingWindowId = homes.windowId;
  if (command == "HOMES") {
    reply.output = homes.commissioned ? String("Connected homes:\n") + homes.description : "No homes paired.";
  }
  if (!reply.pairingCode.isEmpty() &&
      ((command == "PAIR ADD" && !homes.additional) ||
       (command == "PAIR" && homes.commissioned))) {
    reply.pairingCode = "";
    reply.pairingQrPayload = "";
    reply.output = "Pairing changed. Refresh connected homes.";
    reply.ok = false;
  }
  return reply;
}
