#pragma once
#include <stdint.h>

// Settings are independent of the rollback firmware's private configuration.
#if __has_include("private_config.h")
#include "private_config.h"
#endif
// A real relay must have an explicitly configured app authentication key.
#ifndef LOCKLINK_UNLOCK_KEY_HEX
#define LOCKLINK_UNLOCK_KEY_HEX ""
#endif
#ifndef LOCKLINK_RELAY_ENABLED
#define LOCKLINK_RELAY_ENABLED 0
#endif
#ifndef LOCKLINK_RELAY_GPIO
#define LOCKLINK_RELAY_GPIO 2
#endif
#ifndef LOCKLINK_INDICATOR_GPIO
#define LOCKLINK_INDICATOR_GPIO 48
#endif
#ifndef LOCKLINK_ALLOWED_WEB_ORIGIN
#define LOCKLINK_ALLOWED_WEB_ORIGIN ""
#endif

namespace config {
constexpr bool relayEnabled = LOCKLINK_RELAY_ENABLED == 1;
constexpr const char* unlockKeyHex = LOCKLINK_UNLOCK_KEY_HEX;
constexpr const char* allowedWebOrigin = LOCKLINK_ALLOWED_WEB_ORIGIN;
constexpr uint8_t indicatorPin = LOCKLINK_INDICATOR_GPIO;
constexpr uint8_t outputPin = LOCKLINK_RELAY_GPIO;
constexpr bool outputActiveHigh = true;
static_assert(!relayEnabled || (outputPin <= 48 &&
    outputPin != indicatorPin && outputPin != 0 && outputPin != 3 &&
    outputPin != 19 && outputPin != 20 &&
    (outputPin < 22 || outputPin > 37) &&
    outputPin != 43 && outputPin != 44 &&
    outputPin != 45 && outputPin != 46),
    "Choose a safe relay GPIO, separate from the RGB LED");
}

namespace matter_config {
constexpr const char* deviceName = "Door Release";
constexpr uint32_t pulseUs = 2000000;
}
