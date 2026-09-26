#include "local_network.h"
#include <esp_netif.h>

namespace local_network {
Snapshot snapshot() {
  Snapshot result;
  auto* netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
  if (!netif || !esp_netif_is_netif_up(netif)) return result;
  result.linkUp = true;
  esp_netif_ip_info_t info = {};
  if (esp_netif_get_ip_info(netif, &info) == ESP_OK) result.ipv4 = info.ip.addr;
  return result;
}
}
