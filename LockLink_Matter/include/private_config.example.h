#pragma once

// Pairing in Apple/Google/Alexa supplies Wi-Fi; no SSID/password is needed here.
// First test using the board's RGB LED. Enable only after verifying relay wiring.
#define LOCKLINK_RELAY_ENABLED 0
#define LOCKLINK_RELAY_GPIO 2
#define LOCKLINK_INDICATOR_GPIO 48 // Use 38 on boards with the RGB LED on GPIO 38.

// App authentication is separate from Matter pairing and any voice PIN.
// Generate a strong hex key: python -c "import secrets; print(secrets.token_hex(32))"
// Enter the same hex key in the LockLink app's device settings.
#define LOCKLINK_UNLOCK_KEY_HEX ""
#define LOCKLINK_ALLOWED_WEB_ORIGIN ""
