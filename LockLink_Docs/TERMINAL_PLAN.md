# App terminal and optional home setup

## Intended outcome

Settings opens a terminal for an ESP32 already reachable on the local Wi-Fi.
The user can read live LockLink serial messages and type concise commands.
Optional Apple Home, Google Home and Alexa pages run the same commands and
show the real Matter setup code without requiring a USB serial monitor.
Preserve existing output behavior, local-only networking, saved credentials,
and the current Flutter Material theme. Existing uncommitted work stays intact.

## Command contract

Commands are case-insensitive, trimmed, one line, at most 128 ASCII characters.

| Command | Reply | Effect |
| --- | --- | --- |
| `HELP` | `HELP / STATUS / PAIR` plus one short description each | None |
| `STATUS` | Wi-Fi address, Matter paired/unpaired, output mode, armed state, release active/inactive, test VID/PID | None |
| `PAIR` | Manual code, optional Matter QR payload and pairing-window state, or sharing instructions if already paired | Opens the initial commissioning window when needed; never erases an existing home |
| `HOMES` | Connected-home records in authenticated reply metadata | None |
| `PAIR ADD` | Fresh manual/QR code, valid for a 5-minute enhanced commissioning window | Adds another home without erasing existing pairings |
| `PAIR CLOSE` | Confirmation or in-progress error | Closes only a window opened by LockLink; does not interrupt active commissioning |
| `HOME REMOVE <id>` | Confirmation or error | Removes that home, retaining Wi-Fi, other homes and the app key |
| `HOME NAME <id> <UTF-8 hex>` | Confirmation or error | Saves a 1–32-byte home label on the door |
| `RESET MATTER` | `USB only. Erases homes and Wi-Fi.` in app | Existing destructive USB command remains USB-only |
| Unknown | `Unknown command. Type HELP.` | None |

No remote shell, arbitrary memory access, Wi-Fi credential editing, or new
actuator commands. Setup never sends an unlock command. The app HMAC key is
distinct from the Matter setup code. Pairing secrets are returned only to the
requesting authenticated client, not retained in the shared log buffer.

## Transport and logging

- Extend the existing local HTTP server; no new dependency or public service.
- A dedicated `/terminal/challenge` nonce avoids interfering with unlocks.
- `POST /terminal?after=N&boot=ID` has a plain-text command (empty for log reads).
  HMAC covers `terminal:after:boot:command:nonce`. Authenticate reads and writes,
  including LED mode. Up to eight outstanding single-use challenges per endpoint
  allow concurrent phones; unknown nonces do not invalidate other requests.
  A full challenge pool returns a busy response without evicting live nonces. Require a configured firmware signing key; never install
  a firmware key implicitly. Preserve the existing unlock signature protocol.
- Reply has a protocol version, boot ID, latest sequence, bounded log entries,
  history-gap flag, command result, commissioned state, and optional pairing code.
  Protocol version 1 adds optional `pairing_qr_payload` for successful `PAIR`.
  It is the device's actual `MT:` payload from the Matter SDK onboarding helper,
  generated under the stack lock with the manual code's discovery settings.
  It is never the app signing key or an onboarding webpage URL.
- Keep 64 lines of 160 bytes in RAM; mirror application messages to USB.
  This is an application serial monitor, not a capture of ROM/SDK diagnostics.
  No passwords, app keys, or Matter codes enter shared history.
- Poll roughly once per second while visible; serialize requests, stop in the
  background, back off after failures, resume from the cursor, detect reboot and
  dropped history. Never automatically retry a typed command.
- HTTP HMAC authenticates but does not encrypt; this retains the existing
  trusted-LAN transport. Logs and code are not persisted to disk by the app.

## Screens and copy

- Settings: Terminal and optional Smart home setup entries, using saved settings.
- Terminal: connection text, scrollable selectable monospace output, command
  field and Send, HELP/STATUS/PAIR shortcuts, clear/copy actions in menus. Keep
  300 live lines, plus a frozen snapshot of up to 300 lines while reading earlier
  output. Resume at the bottom or with Resume live logs. Redact old code lines
  on background, commissioning, connection error, or detected reboot.
- Errors distinguish unreachable device, rejected key, missing firmware key,
  and unsupported firmware. Clear/copy affect only the current app view.
- Setup: choose ecosystem, see prerequisites, then Get setup code (STATUS then
  PAIR). Show the QR and code with Copy code and Enlarge QR; finish in the
  selected home app. Check pairing becomes the primary action; Get code again
  moves to Pairing options. Supplementary device information stays collapsed.
  After returning from a home app, keep Check pairing available without retaining
  the secret; offer Get code again if needed. Check pairing runs STATUS; it can
  verify a new fabric when management metadata is available; it cannot prove
  that the selected home app has finished displaying the accessory.
- Connected homes: show the live Matter fabric table, with rename/remove in each
  row's menu and Add home app as the primary action. Removal asks for confirmation
  and affects all members of that home. Older firmware shows an update message
  and retains the ecosystem-sharing instructions.
- Already commissioned: `PAIR ADD` creates fresh random credentials and an
  enhanced window. Concurrent phones receive the same temporary code while
  that window is live; requesting it again does not extend the deadline or
  replace another phone's code. Temporary credentials exist only in RAM and
  are cleared on commissioning completion/closure. The command never returns
  the original code or resets the accessory.
  Check pairing compares home IDs to the pre-pairing list; the presence of an
  existing home is not evidence that a new pairing completed.
- New replies include optional `homes` records (`id`, `index`, `vendor_id`,
  `label`), `fabric_capacity`, `pairing_window_open`, `pairing_mode`, and an opaque
  `pairing_window_id`. Replacing a sharing code on one phone invalidates the
  displayed code on other phones at their next refresh.
  IDs use compressed fabric IDs so a delayed remove cannot affect another home
  that later reuses the same fabric index. Commands resolve IDs under the CHIP
  stack lock, and changes are blocked during commissioning/failsafe activity.
- Home labels and membership are persisted by Matter on the door. Foreground
  clients poll about once per second and refresh before enabling changes after
  resuming. Firmware serializes writes; the last successful rename wins if two
  phones rename the same home together. A missed response is never replayed.
- An explicit Terminal send can wait for one current read-only poll, but is
  cancelled by backgrounding, disconnect, or reboot. A reply only clears the
  submitted draft when the user has not changed it while waiting.
- Codes disappear on background, disconnect, reboot, timeout, closed window,
  or a changed home list. `PAIR CLOSE` closes the temporary window; merely hiding
  a code does not cancel a pairing in progress.
- Describe Door Release as the existing momentary switch/outlet. Google and
  Alexa need compatible controllers and development-device acceptance; do not
  promise certification or successful pairing. Use the reported VID/PID.

## Pairing QR

- Guides and Terminal share one locally rendered `qr_flutter` view. Terminal
  offers Show pairing QR after authenticated initial `PAIR` or explicit `PAIR ADD`.
- Use black square modules on white in both themes, with a four-module quiet
  zone. Quantize module pitch to the renderer's half-pixel grid. Inline QR size
  stays at or below 260 logical pixels; the scrollable enlarged dialog uses more
  of the phone width and includes the manual code and Copy code.
- Show: "Scan with another phone's home app, or copy the code to pair on this
  phone." Missing or malformed QR data shows "QR unavailable. Use the setup
  code." and preserves manual pairing with older firmware.
- Clear both codes and remove any open dialog on backgrounding, connection
  failure, reboot or completed pairing. Ignore stale responses, including an
  interrupted guide's STATUS-to-PAIR sequence. Never display initial pairing
  credentials for a device already paired to another home.
- QR payloads never enter logs, copied logs, persistent storage or external
  services. There is no QR export, camera scanner or home-app navigation.

## Implementation and validation

1. Add bounded log buffer, shared command executor, authenticated endpoint.
2. Add typed Flutter response model/client and terminal lifecycle handling.
3. Add setup guides, Settings navigation, and the requested default pairing key.
4. Test request signatures, error handling, setup code/sharing behavior, terminal
   interaction, narrow-screen layout and existing app flows.
5. Run Flutter analysis/tests, native firmware tests, and the ESP32-S3 build.
6. Review copy and layout with Better Design. Report actual checks separately
   from unverified physical hardware, USB/Wi-Fi recovery, and ecosystem pairing.

## Guide references

- [Apple Matter setup](https://support.apple.com/en-gb/102135)
- [Google Matter setup and sharing](https://support.google.com/googlehome/answer/13127223?hl=en-GB)
- [Alexa Matter setup](https://digprjsurvey.amazon.co.uk/csad/help/node/TSWevY1sX8ADH2LC20)

Checked 2026-09-27. Platform wording can change. Bootstrap without Wi-Fi remains
the existing firmware-configured network or Matter BLE commissioning flow.

## Implementation evidence

- Flutter analysis passed. All 38 tests passed. Protocol and widget tests cover command signatures,
  unsupported firmware/rejected keys, invalid commands/cursors, live-log rollover,
  lifecycle pause/resume, code redaction, all three setup guides and narrow layouts.
  QR cases cover valid/missing/malformed/commissioned responses, shared display,
  manual copying, dialog enlargement and dismissal, and stale preparation replies.
- The native suite passed for bounded history, network readiness, lock state and
  release output. The ESP32-S3 build compiled and linked successfully.
- Rendered Flutter widget previews were inspected at 390 and 1440 widths, with
  separate setup previews. The 320-wide/200%-text short-viewport test also passed.
  These use mock device responses, not a live ESP32. No rendered DOM is involved.
- An independent QR decoder recovered the exact sample Matter payload from all
  five QR previews: three guides and mobile/desktop Terminal. This verifies
  rendered encoding, not recognition by a second physical phone.
- The firmware retains the existing release behavior. No board was flashed and
  no physical device, ecosystem commissioning, phone installation, or iOS build
  was verified during this change.
- Install the updated app and flash the updated firmware to use the terminal.
  Configure the same signing key in firmware; the app default change does not
  rewrite firmware credentials or previously saved app credentials.

## Multiple phones and Apple Accounts

A record represents one Matter home/fabric, not one phone or Apple Account.
Devices using the same Apple Account with Home enabled in iCloud share its Home
configuration. Inviting another Apple Account to that Home does not add a fabric;
manage those people and their permissions in Apple Home Settings. Separately
commissioned homes or platforms add separate records, within the SDK capacity.
LockLink cannot infer account email addresses or list invited people from Matter.

Every LockLink app with the same door address and app HMAC key has management
access on the local Wi-Fi, independently of Apple Home membership. Removing a
home does not revoke the app key. Names here label the connected home, not the
accessory name cached by each ecosystem. Wi-Fi survives removal of the last home;
the SDK opens an initial pairing window so the door can be added again. If an
Apple Home removal never reached the door, remove that leftover entry here.

Validation must distinguish automated app/native tests and compilation from real
multi-phone, Apple Home, Google Home, Alexa, and physical network checks.
