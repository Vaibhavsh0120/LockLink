#include "local_network.h"
#include <esp_netif.h>
#include <esp_wifi.h>
#include <esp_event.h>
#include <atomic>

namespace local_network {
namespace {
std::atomic<uint32_t> epoch{0}, disconnects{0};
std::atomic<uint16_t> lastDisconnectReason{0};
void networkEvent(void*, esp_event_base_t base, int32_t id, void* data) {
  if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
    if (data) lastDisconnectReason = static_cast<wifi_event_sta_disconnected_t*>(data)->reason;
    ++disconnects;
    ++epoch;
  } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
    ++epoch;
  }
}
}

bool beginDiagnostics() {
  // No formatting, heap allocation or network mutations in event callbacks.
  const auto wifi = esp_event_handler_register(WIFI_EVENT, WIFI_EVENT_STA_DISCONNECTED, networkEvent, nullptr);
  const auto ip = esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, networkEvent, nullptr);
  return wifi == ESP_OK && ip == ESP_OK;
}

Diagnostics diagnostics() {
  return {epoch.load(), disconnects.load(), lastDisconnectReason.load()};
}

bool prepareBuffers() {
  wifi_mode_t mode;
  // The first initialization owns the counts. Never deinitialize/reconfigure
  // a live driver, which could interrupt its saved network.
  if (esp_wifi_get_mode(&mode) != ESP_ERR_WIFI_NOT_INIT) return false;
  wifi_init_config_t config = WIFI_INIT_CONFIG_DEFAULT();
  // Retain this board's best measured profile. Larger SDK/default packet
  // budgets and alternate aggregation settings did not eliminate link loss.
  config.static_rx_buf_num = 2;
  config.dynamic_rx_buf_num = 4;
  config.tx_buf_type = 1;
  config.static_tx_buf_num = 0;
  config.dynamic_tx_buf_num = 4;
  config.ampdu_rx_enable = 0;
  config.rx_ba_win = 4;
  return esp_wifi_init(&config) == ESP_OK;
}

Snapshot snapshot() {
  static bool responsiveWifi = false;
  static uint32_t configuredEpoch = 0;
  Snapshot result;
  result.epoch = epoch.load();
  if (configuredEpoch != result.epoch) responsiveWifi = false;
  auto* netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
  if (!netif || !esp_netif_is_netif_up(netif)) {
    responsiveWifi = false;
    return result;
  }
  result.linkUp = true;
  esp_netif_ip_info_t info = {};
  if (esp_netif_get_ip_info(netif, &info) == ESP_OK) result.ipv4 = info.ip.addr;
  if (!result.ready()) {
    responsiveWifi = false;
  } else if (!responsiveWifi) {
    // This controller is externally powered. Avoid DTIM sleep delays before
    // local challenge/unlock requests; app_network owns Wi-Fi connection.
    // Retry on failure and reapply after reconnect, without hiding link state.
    responsiveWifi = esp_wifi_set_ps(WIFI_PS_NONE) == ESP_OK;
    if (responsiveWifi) configuredEpoch = result.epoch;
  }
  return result;
}
}
