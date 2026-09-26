#pragma once
#define LOCKLINK_WIFI_SSID "YOUR_WIFI_NAME"
#define LOCKLINK_WIFI_PASSWORD "YOUR_WIFI_PASSWORD"
// Keep relay mode off until wiring and power ratings have been verified.
// Generate a 64-character hex key with: python -c "import secrets; print(secrets.token_hex(32))"
#define LOCKLINK_RELAY_ENABLED 1 // 0 keeps the LED prototype mode; 1 enables the relay output.
#define LOCKLINK_RELAY_GPIO 2
// Matches the app's default pairing value "1234".
#define LOCKLINK_UNLOCK_KEY_HEX "03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4"
// Optional exact local web origin, e.g. "http://localhost:8080".
// Leave empty to allow native Android/iOS apps only in relay mode.
#define LOCKLINK_ALLOWED_WEB_ORIGIN ""
