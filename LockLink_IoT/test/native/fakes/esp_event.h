#pragma once
#include <cstdint>
using esp_event_base_t = const char*;
using esp_event_handler_t = void (*)(void*, esp_event_base_t, int32_t, void*);
inline constexpr char WIFI_EVENT[] = "wifi";
inline constexpr char IP_EVENT[] = "ip";
constexpr int WIFI_EVENT_STA_DISCONNECTED = 5;
constexpr int IP_EVENT_STA_GOT_IP = 1;
int esp_event_handler_register(esp_event_base_t, int32_t, esp_event_handler_t, void*);
