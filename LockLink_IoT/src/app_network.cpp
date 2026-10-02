#include "app_network.h"
#include "config.h"
#include "local_network.h"
#include "reconnect_policy.h"
#include <Arduino.h>
#include <esp_event.h>
#include <esp_netif.h>
#include <esp_wifi.h>
#include <nvs_flash.h>
#include <cstring>

namespace app_network {
namespace {
ReconnectPolicy retries;
uint32_t lastAddress = 0;
bool started = false;
}

bool begin() {
  // Never erase persistent network data to recover an NVS error.
  if (nvs_flash_init() != ESP_OK || esp_netif_init() != ESP_OK) return false;
  const auto events = esp_event_loop_create_default();
  if (events != ESP_OK && events != ESP_ERR_INVALID_STATE) return false;
  if (!local_network::prepareBuffers()) return false;
  if (!esp_netif_create_default_wifi_sta() || !local_network::beginDiagnostics()) return false;
  if (esp_wifi_set_mode(WIFI_MODE_STA) != ESP_OK) return false;
  wifi_config_t saved = {};
  if (esp_wifi_get_config(WIFI_IF_STA, &saved) != ESP_OK) return false;
  // Retain an already saved network. Compile-time credentials seed only a
  // board without one; neither path changes the app key or unrelated storage.
  if (saved.sta.ssid[0] == '\0') {
    if (config::wifiSsid[0] == '\0') return false;
    memcpy(saved.sta.ssid, config::wifiSsid, sizeof(config::wifiSsid) - 1);
    memcpy(saved.sta.password, config::wifiPassword, sizeof(config::wifiPassword) - 1);
    saved.sta.pmf_cfg.capable = true;
    if (esp_wifi_set_config(WIFI_IF_STA, &saved) != ESP_OK) return false;
  }
  if (esp_wifi_start() != ESP_OK) return false;
  if (config::wifiTxPower && esp_wifi_set_max_tx_power(config::wifiTxPower) != ESP_OK) return false;
  started = true;
  lastAddress = millis();
  // A missing router is not a startup failure. poll() retries without blocking
  // USB commands or ever issuing/replaying a release command.
  esp_wifi_connect();
  return true;
}

bool reconnect() {
  if (!started) return false;
  esp_wifi_disconnect();
  lastAddress = millis();
  return esp_wifi_connect() == ESP_OK;
}

void poll() {
  if (!started) return;
  const uint32_t now = millis();
  const bool ready = local_network::snapshot().ready();
  if (ready) lastAddress = now;
  if (!retries.due(now, ready)) return;
  wifi_ap_record_t accessPoint = {};
  if (esp_wifi_sta_get_ap_info(&accessPoint) != ESP_OK) {
    esp_wifi_connect();
  } else if (uint32_t(now - lastAddress) >= 30000) {
    // Association alone does not prove DHCP succeeded. Restart the link after
    // a bounded no-address period instead of remaining permanently stuck.
    reconnect();
  }
}
}
