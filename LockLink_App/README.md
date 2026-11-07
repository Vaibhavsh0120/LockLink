# LockLink app

The v2.2.5 Flutter client for the local ESP32-C3 LockLink controller runs on Android,
iOS, and web. Settings retains Light, Dark, and System appearance and native widgets.

1. Run `flutter pub get` and `flutter run`.
2. Save the ESP32's local HTTP address in Settings. Fresh installs default to
   `192.168.0.112`; saved addresses are retained. Reserve its DHCP address on
   the router to avoid an unexpected address change.
3. Save the private pairing value/signing key matching the firmware. Tap the
   center control or Unlock door. Both use the same single-use HMAC challenge.

Fresh installs use pairing value
`d489653731bf3aeec85cca136a511294c329106e20a0b2627adc2f180146a507`.
Existing saved keys take priority. This value is included in public app builds,
so choose a new private key for a real door. Saving app settings does not change
the firmware's key or configure its Wi-Fi. Share your private key only with
authorized users; all phones with it can request a release.

Android/iOS store keys in platform secure storage; web holds them only in memory.
The foreground control screen prepares one short-lived challenge. It is cleared
on background, Settings, offline state, or disposal. Requests never overlap;
background apps do not keep polling. Unlock is never automatically retried.

When a reply is lost, the output may already have operated. Check the device
before manually retrying. Offline recovery and fresh foreground validation stay
enabled. See [offline behavior](../LockLink_Docs/OFFLINE_BEHAVIOR.md).

Matter, smart-home screens, pairing QR, platform home-app handoffs, and app
Terminal are removed in v2.2.0. No network log history or setup commands remain.
Use [USB health diagnostics](../LockLink_Docs/USB_DIAGNOSTICS.md) when troubleshooting.
Native Android/iPhone gate widgets continue to use the same local authenticated
API. iPhone extensions still require a properly signed direct installation.

The app reports commanded output state, not actual door position. See
[relay setup](../LockLink_Docs/RELAY_SETUP.md) before connecting the physical lock.
