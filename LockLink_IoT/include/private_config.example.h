#pragma once

// Do NOT put your home Wi-Fi password or SSID in this file.
// First pair in Apple Home (or a supported Google/Alexa Matter setup).
// That setup sends the Wi-Fi credentials to the ESP32 over Bluetooth LE;
// Matter saves them on the board and reconnects after a reboot.
// Normal control uses Wi-Fi, not Bluetooth. Use a 2.4 GHz home network.
// A fresh board has no app connection until this pairing step succeeds.
// The LockLink app does not currently provision Wi-Fi itself.
// First test using the board's RGB LED. Enable only after verifying relay wiring.
#define LOCKLINK_RELAY_ENABLED 0
#define LOCKLINK_RELAY_GPIO 2
#define LOCKLINK_INDICATOR_GPIO 48 // Use 38 on boards with the RGB LED on GPIO 38.

// App authentication is separate from Matter pairing and any voice PIN.
// Generate a strong hex key: python -c "import secrets; print(secrets.token_hex(32))"
// Enter the same hex key in the LockLink app's device settings.
#define LOCKLINK_UNLOCK_KEY_HEX ""
#define LOCKLINK_ALLOWED_WEB_ORIGIN ""
