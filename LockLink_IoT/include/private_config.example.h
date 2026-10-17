#pragma once

// Copy to private_config.h only if it does not exist. Enter 2.4 GHz Wi-Fi for
// first installation. Saved credentials take priority on routine updates.
// The firmware owns reconnects; no nearby phone is required to maintain Wi-Fi.
// There is no Bluetooth provisioning. Never publish this file or private builds.
#define LOCKLINK_WIFI_SSID ""
#define LOCKLINK_WIFI_PASSWORD ""
// Preserve calibrated default power. An optional override uses quarter-dBm
// units (e.g. 34 for 8.5 dBm), and requires a fresh installed-location soak.
#define LOCKLINK_WIFI_TX_POWER 0

// ESP32-C3 Super Mini: GPIO4 is HIGH at idle, LOW for the 1.5-second pulse.
// This is the GPIO signal polarity; verify the module's coil/contact behavior.
// Use mode 0 with the relay disconnected for a blue-LED-only first test.
// Relay mode remains unarmed until the valid private app key below is set.
#define LOCKLINK_RELAY_ENABLED 1
#define LOCKLINK_RELAY_GPIO 4
#define LOCKLINK_INDICATOR_GPIO 8 // Blue LED, active LOW (not an RGB LED).

// App authentication uses a private HMAC-SHA256 key.
// Generate a strong hex key: python -c "import secrets; print(secrets.token_hex(32))"
// Enter the same hex key in the LockLink app's device settings.
#define LOCKLINK_UNLOCK_KEY_HEX ""
#define LOCKLINK_ALLOWED_WEB_ORIGIN ""
// For a local browser preview, explicitly allow its exact origins instead:
// #define LOCKLINK_ALLOWED_WEB_ORIGINS "http://localhost:8765", "http://127.0.0.1:8765"
// Remove testing origins before permanent installation. Native apps need no CORS.
