# App terminal and optional home setup

## Intended outcome

Settings opens a terminal for an ESP32 already reachable on the local Wi-Fi.
The user can read live LockLink serial messages and type concise commands.
Optional Apple Home, Google Home and Alexa pages run the same commands and
show the real Matter setup code without requiring a USB serial monitor.
Preserve existing output behavior, local-only networking, saved credentials,
and the current Flutter Material theme. Existing uncommitted work stays intact.

## Command contract

Commands are case-insensitive, trimmed, one line, at most 64 ASCII characters.

| Command | Reply | Effect |
| --- | --- | --- |
| `HELP` | `HELP / STATUS / PAIR` plus one short description each | None |
| `STATUS` | Wi-Fi address, Matter paired/unpaired, output mode, armed state, release active/inactive, test VID/PID | None |
| `PAIR` | Manual code, optional Matter QR payload and pairing-window state, or sharing instructions if already paired | Opens the initial commissioning window when needed; never erases an existing home |
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
  including LED mode. Require a configured firmware signing key; never install
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
  verify Matter commissioning, not which ecosystem owns it.
- Already commissioned: hide the original code and explain how to get a fresh
  sharing code from the existing home app. Never factory-reset to add a home.
- Describe Door Release as the existing momentary switch/outlet. Google and
  Alexa need compatible controllers and development-device acceptance; do not
  promise certification or successful pairing. Use the reported VID/PID.

## Pairing QR

- Guides and Terminal share one locally rendered `qr_flutter` view. Terminal
  offers Show pairing QR only after an authenticated, successful unpaired PAIR.
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
