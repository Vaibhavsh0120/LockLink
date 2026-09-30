# Gate widgets (v1.9.3)

The widget's **Unlock gate** button sends the existing local status/challenge/
signed-unlock sequence without launching Flutter. It uses the address and pairing
value already saved in Settings, including the defaults on a fresh installation.
Open LockLink once after installing/upgrading and allow local-network access.

## Android

Install the APK, open Settings, and tap **Set up widgets**. Confirm the
launcher's pin prompt, or long-press Home Screen → Widgets → LockLink. The native
widget works while Flutter is closed. A locked phone must be unlocked first.
The widget picker offers **Gate · Circle** (1×1) and **Gate · Pill** (2×1).
The circle is a 48dp control; the pill can be widened for more result text.
Both follow the phone's light/dark appearance. Short status labels keep the small
controls readable; the full request result appears as a system message after a
tap and is included in the control's accessibility description. Existing widgets
may retain their old size: resize them or remove and re-add from the picker.
An Android sidebar can host it only if that manufacturer's sidebar supports
standard app widgets; Home Screen is the supported placement.

## iPhone

Interactive widgets require iOS 17 or later.
Home Screen and Today View support small/medium widgets. Lock Screen supports
circular and rectangular widgets. Add LockLink through the system widget picker.
The small Home Screen design is circular; the medium design is a slim pill.
iOS still reserves its standard small/medium grid space around these controls.
Changing the visible shape cannot reduce that system-controlled footprint.
iOS does not allow an app to install a widget without the user choosing it.
The unlock AppIntent requests device authentication when required by iOS.

The Runner and LockLinkWidgets targets must both be signed with a provisioning
profile granting `group.com.locklink.locklink`. Register/enable this App Group
for both identifiers with the signing account. The extension is embedded at
`Runner.app/PlugIns/LockLinkWidgets.appex`. Do not remove it when signing the IPA.
For direct sideloads, keep the widget extension when the installer asks.
AltStore appends the signing team's identifier to App Groups. Both targets now
resolve that installed group from `ALTAppGroups` metadata or the bundled
provisioning profile, then use it consistently for the container, preferences,
and Keychain. The original group is preferred when iOS authorizes it; otherwise
exactly one authorized group in the `group.com.locklink.locklink.` namespace is
required. Unrelated or ambiguous groups are rejected. Profile/Info.plist data
only supplies candidate names: iOS container and Keychain access remain enforced.
This also covers signers that retain a profile but omit AltStore metadata.
Arbitrary group renaming outside that namespace still requires updating both
targets and the shared original group before building.

Sources: [AltStore group rewriting](https://github.com/altstoreio/AltStore/blob/develop/AltStore/Operations/FetchProvisioningProfilesOperation.swift),
[per-bundle metadata](https://github.com/altstoreio/AltStore/blob/develop/AltStore/Operations/ResignAppOperation.swift).

### If setup fails

Setup now preserves the native failure instead of always recommending reopening:

- **Missing widget:** the installed app does not contain `LockLinkWidgets.appex`.
  Install the full app with the signed extension included.
- **Cannot share widget settings:** iOS could not open the shared App Group, or
  Keychain returned `errSecMissingEntitlement`. Re-sign/install both targets with
  profiles that grant the same App Group; retrying or reopening cannot grant it.
- **Unlock your iPhone:** protected Keychain storage is temporarily unavailable.
  Unlock the phone and retry setup.
- **Could not save widget settings:** another storage/synchronization failure.
  Retry setup; update the app if it persists.
- **Widget support is missing:** the native Flutter bridge is unavailable in this
  app build. Install a complete current build.

The App Group itself also authorizes the shared Keychain access group on iOS;
an additional team-prefixed Keychain group is not needed for this implementation.
See [Apple's shared Keychain documentation](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps).
The app checks the embedded extension and shared storage before reporting that
settings were updated. These checks do not prove that iOS registered the extension
in its gallery; installation and both targets' signing still need verification.
Failure cleanup remains best effort when iOS denies access to shared storage.

**LiveContainer:** guest app extensions are not registered as native iOS widgets.
LockLink can run inside LiveContainer, but its Home/Lock Screen widget cannot be
added through that installation. A directly installed, correctly signed app and
extension are required. LiveContainer's own launch widgets are a different
feature and do not execute LockLink's background unlock intent.

See the [LiveContainer maintainer explanation](https://github.com/LiveContainer/LiveContainer/issues/245).

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
requires Xcode on macOS; signed entitlement access, widget presentation,
device authentication and real gate operation need physical-device testing.
The release workflow checks that the widget extension exists in the packaged app.
`RunnerTests` covers original/resigned group selection, unauthorized/ambiguous
groups, and provisioning-profile fallback. The release workflow runs these tests
on a macOS simulator and retains logs/results; they cannot run on Windows.
Simulator tests do not establish signed entitlement access on an iPhone.
The Flutter setup regression test covers distinct
signing and locked-storage guidance, retry, and successful synchronization.
Earlier compact Android layouts were inflated as RemoteViews in an Android 13
emulator and inspected in light/dark mode with 130% text scaling. This is prior
development evidence, not validation of every later app version. Launcher
placement and physical gate operation remain separate device checks; iOS layout
needs macOS/device validation. See [v1.9.3 release notes](releases/v1.9.3.md)
for current checks.
