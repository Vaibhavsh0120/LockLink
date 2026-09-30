#pragma once

// OPTIONAL: copy this file to private_config.h and enter your 2.4 GHz Wi-Fi.
// Used at startup ONLY if the board has no saved Wi-Fi and no Matter pairing.
// Saved credentials win; these fields never overwrite a Home-configured network.
// Leave both empty to let Apple/Google/Alexa supply Wi-Fi during BLE pairing.
// Matter manages reconnects in both cases. No Home hub/phone must remain nearby
// for the ESP32 to stay on Wi-Fi. Do not publish private_config.h or private builds.
#define LOCKLINK_WIFI_SSID ""
#define LOCKLINK_WIFI_PASSWORD ""

// ESP32-C3 Super Mini: HIGH energizes the relay for one second; LOW is idle.
// Use mode 0 with the relay disconnected for a blue-LED-only first test.
// Relay mode remains unarmed until the valid private app key below is set.
#define LOCKLINK_RELAY_ENABLED 1
#define LOCKLINK_RELAY_GPIO 4
#define LOCKLINK_INDICATOR_GPIO 8 // Blue LED, active LOW (not an RGB LED).

// App authentication is separate from Matter pairing and any voice PIN.
// Generate a strong hex key: python -c "import secrets; print(secrets.token_hex(32))"
// Enter the same hex key in the LockLink app's device settings.
#define LOCKLINK_UNLOCK_KEY_HEX ""
#define LOCKLINK_ALLOWED_WEB_ORIGIN ""
