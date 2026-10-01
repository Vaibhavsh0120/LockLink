# LockLink app

The v2.1.0 Flutter client for the local ESP32-C3 LockLink controller runs on Android,
iOS, and the web. Choose light, dark, or system appearance in Settings.

1. Run `flutter pub get` and `flutter run`.
2. Open device settings and enter the ESP32's local HTTP address. Fresh installs
   default to `192.168.0.112`; existing saved addresses remain unchanged.
3. In relay mode, enter the pairing passcode or 64-character signing key matching
   the ESP32's private configuration. Tap the center lock or **Unlock door**;
   the app handles the one-time challenge automatically.

Fresh installs use pairing value
`d489653731bf3aeec85cca136a511294c329106e20a0b2627adc2f180146a507`.
Saved addresses and keys take priority over the app defaults. The app value
must match the ESP32 configuration: this 64-character hexadecimal key is used
directly for signing. App defaults do not change firmware keys. The requested
default key is included in app builds; saved keys remain in secure storage.

While the control screen is active and the relay is ready, the app prepares a
single-use unlock challenge in memory. A tap can then send the signed command
without first waiting for a challenge request. Preparation never releases the
relay. Old or unavailable challenges use the normal authenticated sequence;
backgrounding, opening Settings, going offline and closing the screen discard
prepared access. Unlock requests are never automatically retried.

Android and iOS keep the pairing key in platform secure storage. The web app
keeps it only for the current tab session. Relay mode allows browser access
only from the exact origin configured in the firmware. See the
[root README](../README.md) and [relay setup](../LockLink_Docs/RELAY_SETUP.md).

## Terminal and optional home setup

Save the device address and pairing key, then open **Settings > Terminal** for
live LockLink application logs and `HELP`, `STATUS`, or `PAIR` commands. The
ESP32 must already be reachable on the same Wi-Fi and run the matching firmware.
Both LED and relay modes require a firmware signing key for terminal access.
Older firmware prompts you to update; ROM and SDK boot diagnostics still need USB.

**Settings > Smart home setup** provides optional Apple Home, Google Home and
Alexa guides. They run `STATUS` and `PAIR`, then show the device's Matter QR and
manual code with **Copy code** and **Enlarge QR**. Scan with another phone's
home app, or copy the code to pair on this phone. After `PAIR`, Terminal offers
**Show pairing QR** too. Older firmware without a QR payload keeps manual pairing.
A device already paired to a home needs a fresh sharing code. Choose **Add home app**
in LockLink or use the existing home app's sharing flow. Connected homes support
rename and individual removal; these actions retain Wi-Fi, other homes and the
app key. The list represents Matter homes/fabrics, not individual accounts or phones.
Setup never resets the device or starts a release. Removing a home stops any
active release before removing that pairing.

Pairing buttons stay enabled during background polling and disable during a
command or loss of connection. **Open Apple Home / Google Home / Amazon Alexa**
provides a phone-app handoff. Google on Android can start Matter setup using
the current QR through Play Services; other routes open the installed app and
keep manual setup instructions. Missing apps show a recoverable error.

Pairing codes and open QR views clear when the app leaves the foreground, the
connection fails, the device restarts, or pairing completes. QR generation stays
on the phone; QR payloads never enter terminal logs or persistent storage.

The initial address and app pairing value are placeholders; configure the door's
actual address and a private matching key. Existing saved keys take precedence;
saving app settings does not change the firmware's private configuration.
The app key is not the Matter setup code. See [terminal contract](../LockLink_Docs/TERMINAL_PLAN.md)
for protocol details and hardware verification boundaries.

## When the ESP32 is offline

Control, Terminal commands and setup-code generation wait for a fresh device
connection. Foreground screens retry status automatically; commands are never
replayed on reconnect. Connection help covers power, Wi-Fi, changed addresses
and first-time setup over USB. A lost unlock reply means its outcome is unknown.
Connection error text is red in both light and dark themes; initial connection
checking stays neutral.
See [offline behavior and recovery](../LockLink_Docs/OFFLINE_BEHAVIOR.md).
