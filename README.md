# LockLink

LockLink is a local network door controller for ESP32-S3 N16R8. The default
configuration remains an RGB LED prototype. An explicitly enabled relay mode
can pulse a power-to-unlock 12 V lock for two seconds.

## Folders

- `LockLink_App/` — Flutter app for Android, iOS, and web.
- `LockLink_IoT/` — PlatformIO Arduino firmware for ESP32-S3-DevKitC-1.
- `LockLink_Docs/` — wiring and release notes.

## LED test

1. This configuration uses the board's addressable RGB LED on GPIO 48. The
   ESP32-S3-DevKitC-1 v1.1 uses GPIO 38 instead; set
   `config::indicatorPin` in `LockLink_IoT/include/config.h` to match your
   board. Your tested board uses GPIO 48.
2. Copy `LockLink_IoT/include/private_config.example.h` to
   `LockLink_IoT/include/private_config.h` and enter the Wi-Fi credentials.
   The private file is gitignored.
3. In `LockLink_IoT`, run `pio run -t upload` and `pio device monitor -b 115200`.
   Note the printed `http://...` address and output GPIO.
4. On the same Wi-Fi, run `curl http://DEVICE_IP/status` and
   `curl -X POST http://DEVICE_IP/unlock`. The LED should turn on, then off
   after about two seconds.
5. In `LockLink_App`, run `flutter run`. Open device settings in the app and
   enter the ESP32 address shown by the serial monitor. The address is saved
   locally on this device.

The app polls status every ten seconds and times out requests after four seconds.
It disables Unlock while the device is offline or a pulse is active.

## Real lock

Read [relay setup](LockLink_Docs/RELAY_SETUP.md) before connecting the lock.
Relay mode requires an explicit firmware switch and a private 64-character
pairing key. Enter the same key once in the app's device settings. Unlock then
requests a fresh one-time challenge automatically; there is no code to type
for each use. On Android/iOS the key is stored in platform secure storage.
The web app keeps it only until the tab closes.

The status screen reports whether the ESP32 is online and whether its unlock
output is active. It cannot confirm that the door physically opened; there is
no door-position sensor.

## Mobile releases

Push this repository to GitHub, then open **Actions → Manual mobile release →
Run workflow** and enter a tag such as `v1.0.0`. After verification and both
builds succeed, the workflow creates or updates a GitHub Release containing
`LockLink-Android.apk` and `LockLink-iOS-unsigned.ipa`.

The APK uses the Flutter template's test signing configuration and is for
installation/testing, not Play Store distribution. The IPA is **unsigned**;
it cannot be installed on an iPhone until it is signed with an Apple development
or distribution identity. iOS builds require the GitHub macOS runner and cannot
be validated on this Windows checkout.

## Web and remote access

Build the local web client with `flutter build web`. Serve `build/web` on your
local network for browser testing. The browser must be allowed to reach the ESP32;
web requests are subject to CORS and local network permissions.

**Do not use Vercel as a remote unlock route yet.** Vercel can host the Flutter
static files, but it cannot directly reach a private ESP32 on your Wi-Fi. A
public HTTPS page calling a private HTTP address also faces browser mixed-content
and local-network permission restrictions. Relay mode accepts signed local
commands and disables browser access unless one exact local origin is
configured, but it is not a remote-access service. Remote unlock needs a
separate design and security review.
