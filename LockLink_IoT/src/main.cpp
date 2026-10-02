#include <Arduino.h>
#include <esp_task_wdt.h>
#include "config.h"
#include "local_api.h"
#include "app_network.h"
#include "release_output.h"
#include "unlock_auth.h"
#include "device_console.h"
#include "usb_diagnostics.h"
#include "memory_diagnostics.h"
#include "runtime_diagnostics.h"

ReleaseOutput output;
UnlockAuth auth;
LocalApi localApi(output, auth);
bool ready = false;

void setup() {
  const bool heapTracking = memory_diagnostics::begin();
  const bool outputReady = output.begin();
  Serial.begin(115200);
  if (!runtime_diagnostics::begin()) console.println("Chip temperature unavailable.");
  if (!heapTracking) console.println("Memory allocation tracking unavailable.");
  if (!outputReady) { console.println("Output failed. Release disabled."); return; }
  auth.begin();
  if (config::relayEnabled && !auth.ready()) console.println("Relay not armed. Configure app key.");
  localApi.begin();
  if (!app_network::begin()) {
    output.shutdown();
    console.println("Network startup failed. Release disabled; saved data preserved.");
    return;
  }
  esp_task_wdt_config_t watchdog = {8000, 0, true};
  auto wdt = esp_task_wdt_init(&watchdog);
  if (wdt == ESP_ERR_INVALID_STATE) wdt = esp_task_wdt_reconfigure(&watchdog);
  if (wdt == ESP_OK) enableLoopWDT();
  else console.println("Loop watchdog unavailable.");
  ready = true;
  console.println("Ready. App control only. USB: STATUS or WIFI RECONNECT.");
}

void loop() {
  runtime_diagnostics::poll();
  if (ready) { app_network::poll(); localApi.poll(); }
  // Fixed-size, bounded USB diagnostics. No command history, pairing or unlock.
  static char command[33] = {};
  static unsigned length = 0;
  static bool overflow = false;
  for (unsigned read = 0; read < 64 && Serial.available(); ++read) {
    const char c = Serial.read();
    if (c == '\n' || c == '\r') {
      command[length] = '\0';
      if (!overflow) {
        if (strcmp(command, "STATUS") == 0) printUsbStatus(output, auth);
        else if (strcmp(command, "WIFI RECONNECT") == 0)
          console.println(app_network::reconnect() ? "Wi-Fi reconnect requested." : "Wi-Fi reconnect unavailable.");
        else if (length) console.println("USB diagnostics: STATUS or WIFI RECONNECT.");
      }
      length = 0; overflow = false;
    } else if (!overflow && length < sizeof(command) - 1) {
      command[length++] = c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c;
    } else overflow = true;
  }
  delay(ready ? 2 : 100);
}
