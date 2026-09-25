# LockLink

LockLink is a local network smart door **LED prototype**. The Flutter app sends
`POST /unlock` to an ESP32-S3 N16R8, which lights the board's RGB LED for two seconds.
No relay or real door lock is supported in this milestone.

## Folders

- `LockLink_App/` — Flutter app for Android, iOS, and web.
- `LockLink_IoT/` — PlatformIO Arduino firmware for ESP32-S3-DevKitC-1.
- `LockLink_Docs/` — wiring and release notes.

## Start with the LED

1. This configuration uses the board's addressable RGB LED on GPIO 48. The
   ESP32-S3-DevKitC-1 v1.1 uses GPIO 38 instead; set `config::outputPin` in
   `LockLink_IoT/include/config.h` to match your board. For an external LED,
   select `OutputDriver::digital`, set GPIO 2, and wire the LED through a
   current-limiting resistor to GND.
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
and local-network permission restrictions. More importantly, this LED firmware
has no authentication and must never be connected to a relay or exposed to the
public internet. Remote unlock needs a separate authenticated design and a
security review before physical actuation.
