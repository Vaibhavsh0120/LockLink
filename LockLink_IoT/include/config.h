#pragma once
#include <stdint.h>

// Copy private_config.example.h to private_config.h and set your Wi-Fi details.
#if __has_include("private_config.h")
#include "private_config.h"
#else
#define LOCKLINK_WIFI_SSID ""
#define LOCKLINK_WIFI_PASSWORD ""
#endif

namespace config {
enum class OutputDriver { addressableRgb, digital };
constexpr const char* wifiSsid = LOCKLINK_WIFI_SSID;
constexpr const char* wifiPassword = LOCKLINK_WIFI_PASSWORD;
// The onboard RGB LED uses GPIO 48 on DevKitC-1 v1.0. For an external LED,
// switch to digital and GPIO 2, then wire it through a resistor to GND.
constexpr OutputDriver outputDriver = OutputDriver::addressableRgb;
constexpr uint8_t outputPin = 48;
constexpr bool outputActiveHigh = true;
constexpr uint32_t unlockDurationMs = 2000;
constexpr uint32_t wifiRetryMs = 10000;
constexpr uint16_t serverPort = 80;
}
