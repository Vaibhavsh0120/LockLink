#pragma once
#include <stdint.h>

// Copy private_config.example.h to private_config.h and set your Wi-Fi details.
#if __has_include("private_config.h")
#include "private_config.h"
#else
#define LOCKLINK_WIFI_SSID ""
#define LOCKLINK_WIFI_PASSWORD ""
#endif
#ifndef LOCKLINK_RELAY_ENABLED
#define LOCKLINK_RELAY_ENABLED 0
#endif
#ifndef LOCKLINK_RELAY_GPIO
#define LOCKLINK_RELAY_GPIO 2
#endif
#ifndef LOCKLINK_UNLOCK_KEY_HEX
// SHA-256 of the app's default pairing value, "1234".
#define LOCKLINK_UNLOCK_KEY_HEX "03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4"
#endif
#ifndef LOCKLINK_ALLOWED_WEB_ORIGIN
#define LOCKLINK_ALLOWED_WEB_ORIGIN ""
#endif

namespace config {
enum class OutputDriver { addressableRgb, digital };
constexpr const char* wifiSsid = LOCKLINK_WIFI_SSID;
constexpr const char* wifiPassword = LOCKLINK_WIFI_PASSWORD;
constexpr bool relayEnabled = LOCKLINK_RELAY_ENABLED == 1;
constexpr const char* unlockKeyHex = LOCKLINK_UNLOCK_KEY_HEX;
constexpr const char* allowedWebOrigin = LOCKLINK_ALLOWED_WEB_ORIGIN;
// The onboard RGB LED is a command indicator, not a door-position sensor.
constexpr uint8_t indicatorPin = 48;
constexpr OutputDriver outputDriver = relayEnabled
    ? OutputDriver::digital : OutputDriver::addressableRgb;
constexpr uint8_t outputPin = relayEnabled ? LOCKLINK_RELAY_GPIO : indicatorPin;
// DFR0473 is active HIGH. Use a 10k pulldown on its signal line.
constexpr bool outputActiveHigh = true;
constexpr uint32_t unlockDurationMs = 2000;
constexpr uint32_t wifiRetryMs = 10000;
constexpr uint16_t serverPort = 80;
static_assert(!relayEnabled || (outputPin <= 48 &&
    outputPin != indicatorPin && outputPin != 0 && outputPin != 3 &&
    outputPin != 19 && outputPin != 20 &&
    (outputPin < 22 || outputPin > 37) &&
    outputPin != 43 && outputPin != 44 &&
    outputPin != 45 && outputPin != 46),
    "Choose a safe relay GPIO, separate from the RGB LED");
}
