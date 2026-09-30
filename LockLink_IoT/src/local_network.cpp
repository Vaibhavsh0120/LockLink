#include "local_network.h"
#include <esp_netif.h>
#include <esp_wifi.h>

namespace local_network {
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
