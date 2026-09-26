# LockLink app

Flutter client for the local ESP32-S3 LockLink controller. It runs on Android,
iOS, and the web. Choose light, dark, or system appearance in Settings.

1. Run `flutter pub get` and `flutter run`.
2. Open device settings and enter the ESP32's local HTTP address.
3. In relay mode, enter the pairing passcode or 64-character signing key matching
   the ESP32's private configuration. Tap the center lock or **Unlock door**;
   the app handles the one-time challenge automatically.

Android and iOS keep the pairing key in platform secure storage. The web app
keeps it only for the current tab session. Relay mode allows browser access
only from the exact origin configured in the firmware. See the
[root README](../README.md) and [relay setup](../LockLink_Docs/RELAY_SETUP.md).
