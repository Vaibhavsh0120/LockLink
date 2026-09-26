# Gate widgets (v1.4.0)

The widget's **Unlock gate** button sends the existing local status/challenge/
signed-unlock sequence without launching Flutter. It uses the address and pairing
value already saved in Settings, including the defaults on a fresh installation.
Open LockLink once after installing/upgrading and allow local-network access.

## Android

Install the APK, open Settings, and tap **Set up / update widgets**. Confirm the
launcher's pin prompt, or long-press Home Screen → Widgets → LockLink. The native
widget works while Flutter is closed. A locked phone must be unlocked first.
An Android sidebar can host it only if that manufacturer's sidebar supports
standard app widgets; Home Screen is the supported placement.

## iPhone

Interactive widgets require iOS 17 or later, including the APIs used on iOS 27.
Home Screen and Today View support small/medium widgets. Lock Screen supports
circular and rectangular widgets. Add LockLink through the system widget picker;
iOS does not allow an app to install a widget without the user choosing it.
The unlock AppIntent requests device authentication when required by iOS.

The Runner and LockLinkWidgets targets must both be signed with a provisioning
profile granting `group.com.locklink.locklink`. Register/enable this App Group
for both identifiers with the signing account. The extension is embedded at
`Runner.app/PlugIns/LockLinkWidgets.appex`. Do not remove it when signing the IPA.
If a signing tool changes bundle or App Group identifiers, update the shared
group constant and entitlements consistently before building. A missing or
rewritten group cannot share the widget's configuration and keychain item.

**LiveContainer:** guest app extensions are not registered as native iOS widgets.
LockLink can run inside LiveContainer, but its Home/Lock Screen widget cannot be
added through that installation. A directly installed, correctly signed app and
extension are required. LiveContainer's own launch widgets are a different
feature and do not execute LockLink's background unlock intent.

Maintainer explanation: https://github.com/LiveContainer/LiveContainer/issues/245

## Behavior and limits

- The ESP32 must be reachable on the same local network. These are not remote
  Internet unlock widgets.
- Widget installation, rendering and timeline updates never unlock the gate.
- Only the explicit button sends a command. Rapid Android taps are coalesced;
  concurrent iOS requests are rejected while an action is running.
- Android jobs expire after 15 seconds and are not replayed after interruption.
  Network failures are never automatically retried. If confirmation is lost after
  sending a command, check the gate before trying again.
- Results describe command acceptance, not the physical door position. A displayed
  previous result is not a live online/locked-state indicator.
- Pairing keys are stored in Android Keystore-encrypted configuration or shared
  iOS Keychain, never in widget text or PendingIntent extras.
- Failed settings synchronization clears the previous native widget configuration
  where possible. Settings provides an explicit retry.

## Validation

Windows can build the Android APK and run Flutter/Kotlin checks. An iOS build
requires Xcode on macOS; signed entitlement access, iOS 27 widget presentation,
device authentication and real gate operation need physical-device testing.
The release workflow checks that the widget extension exists in the packaged app.
