#include <cassert>
#include <cstring>
#include <iostream>
#include "esp_netif.h"
#include "esp_wifi.h"
#include "local_network.h"
#include "esp_event.h"

esp_netif_t interface;
bool exists = false, up = false;
uint32_t ip = 0;
int ipResult = ESP_OK;
int powerSaveResult = ESP_OK, powerSaveCalls = 0;
int modeResult = ESP_ERR_WIFI_NOT_INIT, initResult = ESP_OK, initCalls = 0;
esp_event_handler_t wifiHandler = nullptr, ipHandler = nullptr;
int esp_event_handler_register(esp_event_base_t base, int32_t id, esp_event_handler_t handler, void* context) {
  assert(context == nullptr);
  if (base == WIFI_EVENT) { assert(id == WIFI_EVENT_STA_DISCONNECTED); wifiHandler = handler; }
  else { assert(base == IP_EVENT && id == IP_EVENT_STA_GOT_IP); ipHandler = handler; }
  return ESP_OK;
}
esp_err_t esp_wifi_get_mode(wifi_mode_t* mode) {
  *mode = WIFI_MODE_STA;
  return modeResult;
}
esp_err_t esp_wifi_init(const wifi_init_config_t* config) {
  ++initCalls;
  const auto defaults = WIFI_INIT_CONFIG_DEFAULT();
  assert(config->static_rx_buf_num == 2);
  assert(config->dynamic_rx_buf_num == 4);
  assert(config->tx_buf_type == 1 && config->static_tx_buf_num == 0);
  assert(config->dynamic_tx_buf_num == 4);
  assert(config->ampdu_rx_enable == 0);
  assert(config->ampdu_tx_enable == defaults.ampdu_tx_enable);
  assert(config->rx_ba_win <= config->dynamic_rx_buf_num);
  assert(config->rx_ba_win <= 2 * config->static_rx_buf_num);
  assert(config->nvs_enable == 1 && config->magic == 1234);
  return initResult;
}
esp_err_t esp_wifi_set_ps(wifi_ps_type_t mode) {
  assert(mode == WIFI_PS_NONE);
  ++powerSaveCalls;
  return powerSaveResult;
}
esp_netif_t* esp_netif_get_handle_from_ifkey(const char* key) {
  assert(std::strcmp(key, "WIFI_STA_DEF") == 0);
  return exists ? &interface : nullptr;
}
bool esp_netif_is_netif_up(esp_netif_t* netif) { assert(netif == &interface); return up; }
int esp_netif_get_ip_info(esp_netif_t* netif, esp_netif_ip_info_t* info) {
  assert(netif == &interface); info->ip.addr = ip; return ipResult;
}
int main() {
  assert(local_network::prepareBuffers());
  assert(initCalls == 1);
  modeResult = ESP_OK;
  assert(!local_network::prepareBuffers()); // Never reinitialize a live driver.
  assert(initCalls == 1);
  modeResult = -3;
  assert(!local_network::prepareBuffers()); // Do not hide a driver query error.
  assert(initCalls == 1);
  modeResult = ESP_ERR_WIFI_NOT_INIT; initResult = -1;
  assert(!local_network::prepareBuffers()); // Startup must detect allocation failure.
  assert(initCalls == 2);
  assert(!local_network::snapshot().ready()); // Before the station exists.
  assert(powerSaveCalls == 0);
  exists = true; up = true;
  assert(!local_network::snapshot().ready()); // DHCP still pending.
  assert(powerSaveCalls == 0);
  ip = 0x6f00a8c0;
  powerSaveResult = -1;
  assert(local_network::snapshot().ready()); // No Arduino WiFi.begin required.
  assert(powerSaveCalls == 1); // Failed configuration does not hide connectivity.
  powerSaveResult = ESP_OK;
  assert(local_network::snapshot().ipv4 == ip);
  assert(powerSaveCalls == 2); // Retry configuration on the next snapshot.
  assert(local_network::snapshot().ready());
  assert(powerSaveCalls == 2); // No repeated driver calls while connected.
  up = false;
  assert(!local_network::snapshot().ready()); // Cached address after disconnect.
  up = true; ipResult = -1;
  assert(!local_network::snapshot().ready()); // Address query failure.
  ipResult = ESP_OK;
  assert(local_network::snapshot().ready()); // Reconnect.
  assert(powerSaveCalls == 3); // Reapply after loss of network readiness.
  assert(local_network::beginDiagnostics());
  wifi_event_sta_disconnected_t lost;
  lost.reason = 200;
  wifiHandler(nullptr, WIFI_EVENT, WIFI_EVENT_STA_DISCONNECTED, &lost);
  assert(local_network::diagnostics().disconnects == 1);
  assert(local_network::diagnostics().lastDisconnectReason == 200);
  assert(local_network::snapshot().epoch == 1);
  assert(powerSaveCalls == 4); // Rejoin completed between snapshots.
  ipHandler(nullptr, IP_EVENT, IP_EVENT_STA_GOT_IP, nullptr);
  assert(local_network::snapshot().epoch == 2);
  assert(powerSaveCalls == 5); // New IP invalidates socket/configuration epoch.
  ipHandler(nullptr, IP_EVENT, 99, nullptr);
  assert(local_network::snapshot().epoch == 2);
  assert(powerSaveCalls == 5);
  std::cout << "Local network tests passed\n";
}
