#include "local_network.h"
#include <esp_netif.h>
#include <esp_wifi.h>

namespace local_network {
bool prepareBuffers() {
  wifi_mode_t mode;
  // The first initialization owns the counts. Never deinitialize/reconfigure
  // a live driver, which could interrupt Matter or its saved network.
  if (esp_wifi_get_mode(&mode) != ESP_ERR_WIFI_NOT_INIT) return false;
  wifi_init_config_t config = WIFI_INIT_CONFIG_DEFAULT();
  // This C3 shares its heap with Matter, BLE and HTTP. Bound burst allocations
  // instead of using the SDK's throughput-oriented dynamic buffer counts.
  // ESP-IDF recommends disabling AMPDU RX below six static receive buffers.
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
  Snapshot result;
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
    // local challenge/unlock requests; Matter still owns Wi-Fi connection.
    // Retry on failure and reapply after reconnect, without hiding link state.
    responsiveWifi = esp_wifi_set_ps(WIFI_PS_NONE) == ESP_OK;
  }
  return result;
}
}
