# LockLink app

Flutter client for the local ESP32-S3 LockLink controller. It runs on Android,
iOS, and the web. It follows the system light/dark setting.

1. Run `flutter pub get` and `flutter run`.
2. Open device settings and enter the ESP32's local HTTP address.
3. In relay mode, also enter the 64-character pairing key from the ESP32's
   private configuration. The app handles the one-time challenge automatically
   when Unlock is tapped.

Android and iOS keep the pairing key in platform secure storage. The web app
keeps it only for the current tab session. Relay mode allows browser access
only from the exact origin configured in the firmware. See the
[root README](../README.md) and [relay setup](../LockLink_Docs/RELAY_SETUP.md).
