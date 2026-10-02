#pragma once
#include "esp_netif.h"
using esp_err_t = int;

enum wifi_ps_type_t { WIFI_PS_NONE, WIFI_PS_MIN_MODEM, WIFI_PS_MAX_MODEM };
esp_err_t esp_wifi_set_ps(wifi_ps_type_t mode);
constexpr int ESP_ERR_WIFI_NOT_INIT = -2;
enum wifi_mode_t { WIFI_MODE_NULL, WIFI_MODE_STA };
struct wifi_event_sta_disconnected_t { uint16_t reason = 0; };
struct wifi_init_config_t {
  int static_rx_buf_num = 8, dynamic_rx_buf_num = 32;
  int tx_buf_type = 1, static_tx_buf_num = 0, dynamic_tx_buf_num = 32;
  int ampdu_rx_enable = 1, ampdu_tx_enable = 1, rx_ba_win = 6;
  int nvs_enable = 1, magic = 1234;
};
#define WIFI_INIT_CONFIG_DEFAULT() wifi_init_config_t{}
esp_err_t esp_wifi_get_mode(wifi_mode_t* mode);
esp_err_t esp_wifi_init(const wifi_init_config_t* config);
