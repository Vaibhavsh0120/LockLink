<p align="center">
  <img src="LockLink_App/assets/icon/locklink.png" alt="LockLink app logo" width="104" height="104">
</p>

<h1 align="center">LockLink</h1>

<p align="center">
  Local door control from your phone.<br>
  Flutter + ESP32-C3 on your home Wi-Fi.
</p>

<p align="center">
  <a href="LockLink_App"><img src="LockLink_Docs/assets/readme/flutter.svg" alt="Built with Flutter"></a>
  <a href="LockLink_Docs/ESP32_C3_SETUP.md"><img src="LockLink_Docs/assets/readme/esp32-c3.svg" alt="ESP32-C3 Super Mini hardware"></a>
  <a href="LockLink_Docs/MATTER_SETUP.md"><img src="LockLink_Docs/assets/readme/matter.svg" alt="Matter over Wi-Fi firmware"></a>
</p>

<p align="center">
  <a href="#getting-started">Set up device</a> ·
  <a href="#version-updates">Change version</a> ·
  <a href="#mobile-releases">Build apps</a>
</p>

Current source version: **v2.1.0**.

## What LockLink does

| Feature | How it works |
| --- | --- |
| Local control | The app requests a one-second release from the ESP32 on the same network. |
| Connection recovery | Home refreshes on return and retries failed status reads automatically. |
| Terminal | Authenticated diagnostics with the latest 16 device log lines. |
| Gate widgets | Native controls for Android and iPhone; iPhone widgets require a signed installation. |
| Matter | App and paired home controllers use the same release output. Controller requirements are below. |

## How it connects

```mermaid
flowchart TD
    app["LockLink app<br/>Phone / browser"] -->|Local HTTP| device["ESP32-C3<br/>Local HTTP + Matter"]
    home["Home controller<br/>Matter pairing"] -->|Matter / Wi-Fi| device
    device --> pulse["One-second release"]
    pulse --> relay["GPIO4 · Relay"]
    pulse --> led["GPIO8 · LED test"]
    classDef default fill:#f6f4ef,stroke:#707c72,color:#222823
    classDef controller fill:#222823,stroke:#222823,color:#f6f4ef
    class device controller
```

The reported state describes the release output. There is no door-position
sensor, so it cannot confirm that the physical door opened.

## Getting started

1. Use the **ESP32-C3 Super Mini** and follow the
   [installation guide](LockLink_Docs/ESP32_C3_SETUP.md). Start with the relay
   disconnected and LED test mode.
2. Join Wi-Fi through Matter pairing or private firmware configuration. Run
   USB `STATUS` to find the device address.
3. Run the Flutter app, save that address in Settings, and use a matching private
   app key for relay control. Read [relay setup](LockLink_Docs/RELAY_SETUP.md)
   before connecting a lock.

<details>
<summary>LED-only setup and test commands</summary>

1. Disconnect the relay. The Super Mini blue LED is GPIO8, active LOW. The
   firmware uses this physical GPIO directly, rather than an RGB LED driver.
2. Copy `LockLink_IoT/include/private_config.example.h` to
   `LockLink_IoT/include/private_config.h` only if it does not exist. Preserve
   existing private values. Set `LOCKLINK_RELAY_ENABLED 0` for this LED test.
   Wi-Fi credentials can be supplied over Bluetooth during Matter pairing,
   or set `LOCKLINK_WIFI_SSID` and `LOCKLINK_WIFI_PASSWORD` in the private
   config to connect before Home pairing. Saved networks take priority.
3. In `LockLink_IoT`, run `pio run -e esp32-c3-supermini -t upload`, then
   `pio device monitor -b 115200`. This environment pins pioarduino
   `55.03.312-1` / Arduino-ESP32 `3.3.12` and the Matter partition layout.
4. Follow the [Apple Home quickstart](LockLink_Docs/APPLE_HOME_QUICKSTART.md)
   to pair, then **Unlock Door Release**. The LED should turn off after one
   second. USB `STATUS` reports current connectivity; `PAIR` shows setup
   information. Keep the pairing code private.
5. Use the IPv4 address reported after commissioning for
   `curl http://DEVICE_IP/status`. In LED mode only,
   `curl -X POST http://DEVICE_IP/unlock` tests the same pulse.
6. In `LockLink_App`, run `flutter run`, enter the reported device address in
   Settings, and tap **Save device**. Relay control also requires the matching
   private app key; the example firmware key is empty.

</details>

<details>
<summary>Appearance, polling and reconnect behavior</summary>

Settings has Light, Dark, and System appearance modes and a haptic feedback
switch on Android/iOS. These preferences save automatically. System is the
default appearance mode and follows the phone's theme.

The active home screen checks the ESP32's shared release state 500 ms after
each completed status read, with a four-second request timeout. After a failed
read, retries wait one second, then two seconds, then five seconds. Polling pauses in the background and in device settings;
returning refreshes the state immediately. Matter and the app control the same
output. Network delays and each platform's refresh behavior still apply.
It disables Unlock while the device is offline or a pulse is active.
After returning to the app, control waits for a fresh status response. See
[offline behavior and recovery](LockLink_Docs/OFFLINE_BEHAVIOR.md) for power loss,
network changes, unconfirmed commands, widgets and first-time setup.

</details>

## Version updates

`LockLink_App/pubspec.yaml` is the single source for the release version and
build number. For future updates, run one command from the repository root—for
example:

```bash
python .github/scripts/sync_version.py --set 2.2.0+220
```

This synchronizes Settings, firmware, all three iOS widget configurations and
current docs. Use your next version and build number in place of `2.2.0+220`.
If you edit the `version:` field yourself, run
`python .github/scripts/sync_version.py` afterward.

New versions get a draft release-notes file; write the changes and
verification results there, then remove its draft marker. Historical release
notes and dated diagnoses are preserved. CI rejects unsynchronized metadata,
and publication rejects draft notes.

## Mobile releases

Version **2.1.0** improves automatic connection recovery and ESP32-C3 memory
usage while retaining Terminal, connected-home management and native widgets.
Both the center circular control and the Unlock button request the same release.
See [v2.1.0 release notes](LockLink_Docs/releases/v2.1.0.md)
for this version's changes and validation boundaries. Older
[v1.5.0 notes](LockLink_Docs/releases/v1.5.0.md) remain historical.

Push this repository to GitHub, then open **Actions → Manual mobile release →
Run workflow**. There is no version input: the workflow reads `pubspec.yaml`,
derives its tag, and checks GitHub before building. If that release already
exists, it stops and tells you to change the source version and synchronize it.
After workflow validation, C3 firmware checks and both mobile builds succeed,
it checks again before creating a new GitHub Release containing
`LockLink-Android.apk` and `LockLink-iOS-unsigned.ipa`.

| Artifact | Use |
| --- | --- |
| `LockLink-Android.apk` | Android installation and testing. |
| `LockLink-iOS-unsigned.ipa` | iPhone build; signing is required before installation. |

The APK uses the Flutter template's test signing configuration and is for
installation/testing, not Play Store distribution. The IPA is **unsigned**;
it cannot be installed on an iPhone until it is signed with an Apple development
or distribution identity. iOS builds require the GitHub macOS runner and cannot
be validated on this Windows checkout.

<details>
<summary>Release checks and public firmware artifacts</summary>

The tag must match the app source version and resolve to the workflow's source
commit if it already exists. README, firmware, app footer, widget versions and
current release notes must agree. Manual release runs are serialized. The macOS
job also runs native widget tests and retains diagnostic logs and test results.
App pushes and pull requests also run **Mobile checks** for version consistency,
Flutter analysis/tests, Android compilation, and native widget tests. Firmware
checks build all four firmware images and run the native behavior suites.
Android workflows use Java 17. **Workflow checks** uses a pinned, checksum-verified
actionlint binary to validate all workflow files. The release reuses those
checks and refuses publication if any required job fails. Public firmware
artifacts are unarmed and exclude private configuration.

</details>

## Widgets

Native gate widgets are available for Android Home Screen and iPhone
Home Screen, Today View, and Lock Screen. See [widget setup](LockLink_Docs/WIDGETS.md)
and the original [v1.4.0 widget release notes](LockLink_Docs/releases/v1.4.0.md). iPhone widgets require
a direct installation with the extension signed; LiveContainer guest installs
cannot expose the widget to iOS.

## Smart home

Pairing uses the firmware's Matter **Door Release** accessory. See the
[Apple Home quickstart](LockLink_Docs/APPLE_HOME_QUICKSTART.md) or the full
[Matter setup guide](LockLink_Docs/MATTER_SETUP.md).

<details>
<summary>Apple Home, Siri, Google Home and Alexa requirements</summary>

The firmware exposes **Door Release** as a Matter door lock. **Unlock** requests
a one-second release; **Lock** ends it early. Repeated Unlock commands do not
extend the pulse. Reported Locked/Unlocked states describe the release output,
not the physical door position. Anyone authorized by a paired controller to
unlock the accessory can release the door; Wi-Fi membership alone does not
identify the owner.

Apple documents [local Wi-Fi Matter control without a home hub on iOS 18+](https://support.apple.com/en-us/102135).
Google Home and Alexa require compatible Matter controllers. [Google disables
Matter door-lock voice unlock and remote unlock for locks without mandatory
PINs](https://developers.home.google.com/matter/supported-devices#door-locks).
Siri/Alexa permissions, authentication and development-device acceptance
need testing on the actual controller. No integration subscription is built
into this project. The existing Android/iPhone app keeps
its authenticated local control. Start with the [Apple Home quickstart](LockLink_Docs/APPLE_HOME_QUICKSTART.md).
Follow [Matter setup](LockLink_Docs/MATTER_SETUP.md)
for configuration, development-accessory pairing, build instructions, and
physical verification requirements. Actual ecosystem pairing remains unverified.

</details>

## Hardware and diagnostics

The current firmware targets the ESP32-C3 Super Mini with 4 MB flash and no
PSRAM. Relay wiring and authentication details are in the
[relay guide](LockLink_Docs/RELAY_SETUP.md).

<details>
<summary>GPIO behavior and private app key setup</summary>

LockLink is a local network door controller for ESP32-C3 Super Mini (4 MB flash,
no PSRAM). GPIO4 is **HIGH at idle and LOW for one second**; GPIO8 drives
the onboard active-LOW blue LED. Relay mode is the default, and requires a valid
private app key before any app or Matter command can start a release pulse.
Signal polarity does not identify physical coil state: a HIGH-ON relay stays
energized at idle with this inverted configuration. Check the wiring guide.

Read [relay setup](LockLink_Docs/RELAY_SETUP.md) before connecting the lock.
Relay mode is enabled by default and requires a matching private app key.
Generate a private 64-character hexadecimal key for `LOCKLINK_UNLOCK_KEY_HEX`
and enter the same key once in the app. An empty or invalid key leaves relay
mode unarmed. The app accepts a 4–64 character pairing value and derives its signing
key with SHA-256; an existing 64-character hexadecimal key is used directly.
To change a text pairing value manually, put its SHA-256 hex digest into
`LOCKLINK_UNLOCK_KEY_HEX` and the original value into app settings. Unlock then
requests a fresh one-time challenge automatically; there is no code to type
for each use. On Android/iOS the key is stored in platform secure storage.
The web app keeps it only until the tab closes.

The status screen reports whether the ESP32 is online and whether its unlock
output is active. It cannot confirm that the door physically opened; there is
no door-position sensor.

</details>

<details>
<summary>USB diagnostics and firmware updates</summary>

Type `STATUS` and Enter to check firmware version, Matter commissioning, the
local IP, and release output. Test `GET /status` for app connectivity.
A single `ESP_ERR_WIFI_CONN` / “sta is connecting”
message during startup means a connection attempt was already in progress;
it does not establish an ongoing failure. Check the later state before
changing configuration. See [recovery guidance](LockLink_Docs/MATTER_SETUP.md#pairing-information-reset-and-recovery)
for persistent connection problems. `RESET MATTER` deliberately clears Matter
pairing/network settings; ordinary firmware updates should not erase them.
Use the normal PlatformIO upload for updates. The combined factory image
wipes NVS and is for initial installation or deliberate recovery.

</details>

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

## Guides

| Guide | Start here when you want to… |
| --- | --- |
| [ESP32-C3 setup](LockLink_Docs/ESP32_C3_SETUP.md) | Install firmware or migrate to the C3 board. |
| [Relay setup](LockLink_Docs/RELAY_SETUP.md) | Connect and configure the relay and lock. |
| [Apple Home quickstart](LockLink_Docs/APPLE_HOME_QUICKSTART.md) | Set up the accessory in Apple Home. |
| [Matter setup](LockLink_Docs/MATTER_SETUP.md) | Understand commissioning, sharing and controller requirements. |
| [Widget setup](LockLink_Docs/WIDGETS.md) | Add native Android or iPhone controls. |
| [Offline recovery](LockLink_Docs/OFFLINE_BEHAVIOR.md) | Diagnose connection, power or network changes. |
| [Terminal reference](LockLink_Docs/TERMINAL_PLAN.md) | Use authenticated diagnostics and smart-home setup. |
| [Connection diagnosis](LockLink_Docs/CONNECTION_DIAGNOSIS_2026-10-01.md) | Read the measured C3 memory and recovery results. |

## Repository

| Folder | Contents |
| --- | --- |
| [`LockLink_App/`](LockLink_App/) | Flutter client for Android, iOS and web. |
| [`LockLink_IoT/`](LockLink_IoT/) | ESP32-C3 Matter firmware and local HTTP API. |
| [`LockLink_Docs/`](LockLink_Docs/) | Wiring, setup, diagnostics and release notes. |
