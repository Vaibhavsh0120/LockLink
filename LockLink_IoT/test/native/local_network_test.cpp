#include <cassert>
#include <cstring>
#include <iostream>
#include "esp_netif.h"
#include "local_network.h"

esp_netif_t interface;
bool exists = false, up = false;
uint32_t ip = 0;
int ipResult = ESP_OK;
esp_netif_t* esp_netif_get_handle_from_ifkey(const char* key) {
  assert(std::strcmp(key, "WIFI_STA_DEF") == 0);
  return exists ? &interface : nullptr;
}
bool esp_netif_is_netif_up(esp_netif_t* netif) { assert(netif == &interface); return up; }
int esp_netif_get_ip_info(esp_netif_t* netif, esp_netif_ip_info_t* info) {
  assert(netif == &interface); info->ip.addr = ip; return ipResult;
}
int main() {
  assert(!local_network::snapshot().ready()); // Before Matter creates Wi-Fi.
  exists = true; up = true;
  assert(!local_network::snapshot().ready()); // DHCP still pending.
  ip = 0x6f00a8c0;
  assert(local_network::snapshot().ready()); // No Arduino WiFi.begin required.
  assert(local_network::snapshot().ipv4 == ip);
  up = false;
  assert(!local_network::snapshot().ready()); // Cached address after disconnect.
  up = true; ipResult = -1;
  assert(!local_network::snapshot().ready()); // Address query failure.
  ipResult = ESP_OK;
  assert(local_network::snapshot().ready()); // Reconnect.
  std::cout << "Local network tests passed\n";
}
