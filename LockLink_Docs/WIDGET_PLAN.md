# Gate widgets implementation plan

Goal: unlock the configured gate from iPhone Lock Screen, Home Screen and Today
View, and Android Home Screen, without opening Flutter for the unlock action.

Architecture: Flutter synchronizes the active address and derived signing key
over `com.locklink/widgets`. Native widgets own their background network request.
Android uses RemoteViews and one-time WorkManager work; iOS uses WidgetKit and
an authenticated AppIntent. Both reuse the current status/challenge/HMAC protocol.

Constraints: preserve existing device defaults, pairing compatibility and UI.
Never unlock on refresh, installation, timeline updates, or background polling.
Never retry POST automatically. Coalesce rapid taps; discard delayed Android work.
Store credentials in Android Keystore-encrypted storage and shared iOS Keychain.
Show command acceptance, never claim a door sensor confirmed opening.

- [x] Flutter bridge: synchronize on startup and device save; expose widget setup
  and retry in Settings. Test bridge payload and failed synchronization.
- [x] Android: encrypted config, explicit button PendingIntent, worker, manifest,
  resources and pin request. Debug and release APKs built; protocol failure/no-retry tests pass.
  Duplicate-work policy reviewed; scheduler lifecycle requires device testing.
- [x] iOS: shared keychain/config, URLSession signed client, AppIntent, WidgetKit
  families, extension target, embedding, entitlements and release packaging check.
- [x] Review: inspect settings/native UI source and permission/setup paths, run Flutter
  tests and analyzer, Android build; document iOS signing/device validation limits.

Review focus: stale credentials after settings changes; locked/unconfigured phone;
duplicate or stale requests; response lost after POST; extension entitlements and
same-network permission. App Groups require provisioning on the signing account.

Validation: 10 Flutter tests and 4 Kotlin tests passed; analyzer clean. Settings
rendered at 390 and 1440 logical pixels in light/dark themes with no overflow.
Xcode project parsed with all new source paths and object references resolved;
plists/entitlements parsed. iOS compilation and native widget renders remain
unverified without Xcode/devices. No connected Android device was available.

Final review: independent reviewer found ambiguous post-send errors could imply
rejection. Fixed both clients to report unconfirmed actuation; Android regression
test reproduced the failure and passed after the fix (oversized/malformed 200 and
unknown status; one POST only; cancelled preflight sends no POST).

Release scope: v1.4.0+14, based on GitHub releases through v1.3.1. LiveContainer
cannot register guest widget extensions; direct signed installation is required.
Changes remain local; publishing was not requested.

Release APK metadata verified: com.locklink.locklink, version 1.4.0, build 14,
with the AppWidget receiver and provider metadata packaged.
