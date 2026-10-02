#include "usb_diagnostics.h"
#include "config.h"
#include "device_console.h"
#include "local_network.h"
#include "memory_diagnostics.h"
#include "runtime_diagnostics.h"
#include <IPAddress.h>
#include <esp_wifi.h>

void printUsbStatus(ReleaseOutput& output, UnlockAuth& auth) {
  const auto memory = memory_diagnostics::snapshot();
  const auto network = local_network::snapshot();
  const auto events = local_network::diagnostics();
  const auto runtime = runtime_diagnostics::snapshot();
  wifi_ap_record_t accessPoint = {};
  const bool associated = esp_wifi_sta_get_ap_info(&accessPoint) == ESP_OK;
  wifi_ps_type_t powerSave = WIFI_PS_NONE;
  const bool powerSaveKnown = esp_wifi_get_ps(&powerSave) == ESP_OK;
  int8_t txPower = 0;
  const bool txKnown = esp_wifi_get_max_tx_power(&txPower) == ESP_OK;
  console.printf("LockLink v%s\n", config::version);
  console.print("Wi-Fi: "); console.println(network.ready() ? IPAddress(network.ipv4).toString() : "offline");
  console.printf("Wi-Fi link: %s\n", associated ? "connected" : "disconnected");
  if (associated) console.printf("Signal: %d dBm\n", accessPoint.rssi);
  if (txKnown) console.printf("Wi-Fi TX limit: %.2f dBm\n", txPower * 0.25f);
  console.printf("Modem sleep: %s\n", !powerSaveKnown ? "unknown" : powerSave == WIFI_PS_NONE ? "off" : "on");
  console.printf("Uptime: %lu s; free heap: %u bytes\n", (unsigned long)runtime.uptimeSeconds, (unsigned)memory.free);
  console.printf("Heap minimum: %u bytes; largest block: %u bytes\n", (unsigned)memory.minimum, (unsigned)memory.largest);
  console.printf("Allocation failures: %lu; last request: %u bytes\n", (unsigned long)memory.allocationFailures, (unsigned)memory.lastFailedBytes);
  console.printf("Reset reason: %lu\n", (unsigned long)runtime.resetReason);
  console.printf("Wi-Fi disconnects: %lu; last reason: %u\n", (unsigned long)events.disconnects, events.lastDisconnectReason);
  if (runtime.temperatureAvailable) console.printf("Chip temperature: %.1f C; peak: %.1f C\n", runtime.temperature, runtime.maximumTemperature);
  console.printf("Temperature read failures: %lu\n", (unsigned long)runtime.temperatureFailures);
  console.printf("Loop max gap: %lu ms; stack minimum: %lu bytes\n", (unsigned long)runtime.maxLoopGapMs, (unsigned long)runtime.loopStackMinimum);
  console.printf("Output: %s; armed: %s\n", config::relayEnabled ? "relay" : "LED", !config::relayEnabled || auth.ready() ? "yes" : "no");
  console.printf("Release: %s\n", output.active() ? "active" : "inactive");
}
