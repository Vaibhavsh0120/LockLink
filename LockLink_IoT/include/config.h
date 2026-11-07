#pragma once
#include <stdint.h>

#if defined(ARDUINO_ARCH_ESP32)
#include <sdkconfig.h>
#if !defined(CONFIG_IDF_TARGET_ESP32C3)
#error "LockLink v2.2.5 requires the ESP32-C3 Super Mini target"
#endif
#endif

// Keep local Wi-Fi and app authentication out of public builds.
#if !defined(LOCKLINK_IGNORE_PRIVATE_CONFIG) && __has_include("private_config.h")
#include "private_config.h"
#endif
#ifndef LOCKLINK_WIFI_SSID
#define LOCKLINK_WIFI_SSID ""
#endif
#ifndef LOCKLINK_WIFI_PASSWORD
#define LOCKLINK_WIFI_PASSWORD ""
#endif
// A real relay must have an explicitly configured app authentication key.
#ifndef LOCKLINK_UNLOCK_KEY_HEX
#define LOCKLINK_UNLOCK_KEY_HEX ""
#endif
#ifndef LOCKLINK_RELAY_ENABLED
#define LOCKLINK_RELAY_ENABLED 1
#endif
#ifndef LOCKLINK_RELAY_GPIO
#define LOCKLINK_RELAY_GPIO 4
#endif
#ifndef LOCKLINK_INDICATOR_GPIO
#define LOCKLINK_INDICATOR_GPIO 8
#endif
#ifndef LOCKLINK_ALLOWED_WEB_ORIGIN
#define LOCKLINK_ALLOWED_WEB_ORIGIN ""
#endif
#ifndef LOCKLINK_ALLOWED_WEB_ORIGINS
#define LOCKLINK_ALLOWED_WEB_ORIGINS LOCKLINK_ALLOWED_WEB_ORIGIN
#endif
#ifndef LOCKLINK_WIFI_TX_POWER
#define LOCKLINK_WIFI_TX_POWER 0
#endif

namespace config {
// Synchronized from LockLink_App/pubspec.yaml; use sync_version.py to change it.
constexpr char version[] = "2.2.5";
constexpr char wifiSsid[] = LOCKLINK_WIFI_SSID;
constexpr char wifiPassword[] = LOCKLINK_WIFI_PASSWORD;
static_assert(sizeof(wifiSsid) <= 33, "Wi-Fi SSID must be at most 32 bytes");
static_assert(sizeof(wifiPassword) <= 65, "Wi-Fi password must be at most 64 bytes");
constexpr bool relayEnabled = LOCKLINK_RELAY_ENABLED == 1;
constexpr const char* unlockKeyHex = LOCKLINK_UNLOCK_KEY_HEX;
constexpr const char* allowedWebOrigins[] = {LOCKLINK_ALLOWED_WEB_ORIGINS};
// Zero preserves the calibrated SDK default; overrides use quarter-dBm units.
constexpr int8_t wifiTxPower = LOCKLINK_WIFI_TX_POWER;
static_assert(LOCKLINK_WIFI_TX_POWER == 0 || (LOCKLINK_WIFI_TX_POWER >= 8 && LOCKLINK_WIFI_TX_POWER <= 84),
    "Wi-Fi TX maximum must be 0 (SDK default) or 8..84 in quarter-dBm units");
constexpr uint8_t indicatorPin = LOCKLINK_INDICATOR_GPIO;
constexpr uint8_t outputPin = LOCKLINK_RELAY_GPIO;
// GPIO4 drives a high-level-trigger 3 V relay (SRD-DC03V-SL-C).
// LOW at idle, HIGH for the 1.5-second release pulse.
constexpr bool outputActiveHigh = true;
constexpr bool indicatorActiveHigh = false;
// Super Mini exposed pins only; exclude boot straps and the blue LED.
static_assert(!relayEnabled || (outputPin <= 10 && outputPin != 2 &&
    outputPin != 8 && outputPin != 9 && outputPin != indicatorPin),
    "Choose a C3 Super Mini relay GPIO (default 4), excluding boot straps/LED");
static_assert(indicatorPin <= 10 && indicatorPin != 2 && indicatorPin != 9,
    "Choose a C3 Super Mini indicator GPIO (blue LED is 8)");
constexpr uint32_t pulseMs = 1500;
constexpr uint32_t pulseUs = pulseMs * 1000;
}
