#pragma once
#include <cstdint>
struct esp_netif_t {};
struct esp_ip4_addr_t { uint32_t addr; };
struct esp_netif_ip_info_t { esp_ip4_addr_t ip; };
constexpr int ESP_OK = 0;
esp_netif_t* esp_netif_get_handle_from_ifkey(const char*);
bool esp_netif_is_netif_up(esp_netif_t*);
int esp_netif_get_ip_info(esp_netif_t*, esp_netif_ip_info_t*);
