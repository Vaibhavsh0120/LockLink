# LockLink

LockLink is a local network door controller for ESP32-S3 N16R8. The default
configuration remains an RGB LED prototype. An explicitly enabled relay mode
can pulse a power-to-unlock 12 V lock for two seconds.

## Folders

- `LockLink_App/` — Flutter app for Android, iOS, and web.
- `LockLink_IoT/` — PlatformIO Arduino firmware for ESP32-S3-DevKitC-1.
- `LockLink_Matter/` — alternate ESP32-S3 Matter firmware for a momentary
  **Door Release** switch in Apple Home, Google Home, and Alexa.
- `LockLink_Docs/` — wiring and release notes.

## Apple Home, Siri, Google Home, and Alexa

The alternate Matter firmware exposes **Door Release** as a switch/outlet:
turning it On requests a two-second release, then it automatically turns Off.
It uses one-time Matter pairing and no door-lock voice PIN. Anyone authorized
to operate this switch can release the door; Wi-Fi membership alone does not
identify the owner. Off describes the output, not the physical door position.

Apple documents local Wi-Fi Matter control without a home hub on iOS 18+.
Google Home and Alexa require compatible Matter controllers. No integration
subscription is built into this project. The existing Android/iPhone app keeps
its authenticated local control. Start with the [Apple Home quickstart](LockLink_Docs/APPLE_HOME_QUICKSTART.md).
Follow [Matter setup](LockLink_Docs/MATTER_SETUP.md)
for configuration, development-accessory pairing, build instructions, and
physical verification requirements. Actual ecosystem pairing remains unverified.

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
5. In `LockLink_App`, run `flutter run`. Settings starts with device address
   `192.168.0.111` and pairing key `1234`. Existing saved values take precedence.
   Change the address if the ESP32 reports a different one, then tap **Save device**.

Settings has Light, Dark, and System appearance modes and a haptic feedback
switch on Android/iOS. These preferences save automatically. System is the
default appearance mode and follows the phone's theme.

The app polls status every ten seconds and times out requests after four seconds.
It disables Unlock while the device is offline or a pulse is active.

## Real lock

Read [relay setup](LockLink_Docs/RELAY_SETUP.md) before connecting the lock.
Relay mode requires an explicit firmware switch and a matching pairing key.
The default firmware signing key is SHA-256 of `1234`, matching the app's
default. The app accepts a 4–64 character pairing value and derives its signing
key with SHA-256; an existing 64-character hexadecimal key is used directly.
To change a text pairing value manually, put its SHA-256 hex digest into
`LOCKLINK_UNLOCK_KEY_HEX` and the original value into app settings. Unlock then
requests a fresh one-time challenge automatically; there is no code to type
for each use. On Android/iOS the key is stored in platform secure storage.
The web app keeps it only until the tab closes.

The status screen reports whether the ESP32 is online and whether its unlock
output is active. It cannot confirm that the door physically opened; there is
no door-position sensor.

## Mobile releases

Version **1.5.0** introduced focused door control and compact responsive settings.
The current source keeps the light theme and uses neutral black/grays in dark
mode. Both the center circular control and the Unlock button request the same
authenticated release. See [v1.5.0 release notes](LockLink_Docs/releases/v1.5.0.md)
for the published release.

Native gate widgets are available for Android Home Screen and iPhone
Home Screen, Today View, and Lock Screen. See [widget setup](LockLink_Docs/WIDGETS.md)
and the original [v1.4.0 widget release notes](LockLink_Docs/releases/v1.4.0.md). iPhone widgets require
a direct installation with the extension signed; LiveContainer guest installs
cannot expose the widget to iOS.

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
