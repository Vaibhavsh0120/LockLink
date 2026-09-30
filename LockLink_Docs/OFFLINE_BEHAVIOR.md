# Device offline and recovery (v1.9.2)

LockLink cannot tell a powered-off ESP32 from a wrong address, a different Wi-Fi
network, blocked local traffic, or a lost reply. It reports an unreachable device
and offers power, Wi-Fi and address checks. It never treats missing data as a
verified door position.

| Situation | Behavior and recovery |
| --- | --- |
| Device off or unreachable at app launch | Show connection checking until the first request finishes, then Offline. Unlock, setup-code generation and Terminal commands stay disabled. Settings and guide navigation remain available. |
| Saved settings or secure storage cannot be read | Stop loading, keep control disabled, and offer Open Settings. Retry loading there; returning reloads the saved address and key, including after a partially failed save. |
| Wi-Fi disappears while the app is open | The next request fails or times out. Disable device actions, clear pairing secrets and any open QR dialog, and discard current setup metadata. Existing terminal logs stay readable. |
| Device comes back at the same address | Foreground screens retry read-only status/log requests after five seconds. Restore actions after a fresh successful response. Never automatically resend PAIR or Unlock. |
| App returns from the background or Settings | Revalidate the connection before allowing control. Old responses cannot restore the previous online state or pairing secrets. |
| Unlock reply is lost | Report “No confirmation. Check the device before retrying.” The ESP32 may already have accepted the command; do not infer failure or send another automatically. |
| Router assigns another IP | Automatic reads keep using the saved address. Check the new address over USB/router and update Settings. LockLink does not scan the network automatically. |
| Device has never joined Wi-Fi | App Terminal cannot reach it. Power it on, open USB serial at 115200 baud and run `PAIR` to obtain the initial Matter code. Use that code for Bluetooth commissioning in the chosen home app, or connect using the configured firmware network. |
| Device is already in another home | Use LockLink Smart home setup → Add home app for a fresh sharing code, or use that home's Matter sharing flow. Do not use the initial code or reset the device to add another home. |
| Wrong app key or older firmware | Terminal/setup show a specific key or firmware error instead of repeatedly retrying it. Correct Settings or firmware, then retry. |

## Request and firmware behavior

Flutter uses a four-second deadline per HTTP request, including response-body
reads. On timeout it signals transport cancellation with `AbortableRequest`;
polling can reuse the client afterward. Cancellation cannot undo a command
already received by the ESP32. A challenge plus command can involve two requests.
All app and widget clients reject HTTP redirects. Device addresses must be bare
local HTTP URLs, with ordinary decimal IPv4 octets (no leading zeroes) or a
`.local`/`localhost` host and an optional port from 1 to 65535. Unsafe saved
addresses are rejected before transport; correct the address in Settings.

Android and iOS widgets check device status before attempting a release, use
bounded requests and keep uncertain-result messages. Android work expires after
15 seconds and does not replay an interrupted command. Widget results are the
last attempt, not a live connection indicator.
Widgets require a recognized idle output state before sending a command. Relay
status must explicitly report an armed output. A busy HTTP 503 response does not
prove the relay is unarmed; clients describe it as busy or unavailable.

The firmware keeps Matter in charge of Wi-Fi reconnects. Local HTTP stops when
Wi-Fi/IPv4 is unavailable and starts again when the interface is ready. Network
failure does not erase Wi-Fi or Matter pairing. Existing saved credentials take
precedence over firmware defaults; changing a default SSID does not migrate a
commissioned device. See [Matter recovery](MATTER_SETUP.md#pairing-information-reset-and-recovery).

The existing release cutoff runs independently of network handling and the
output initializes inactive at boot. This describes firmware behavior, not a
guarantee about the physical lock's state during power loss. Home-controller
offline messages and recovery timing are managed by their respective ecosystems.

## Verification boundaries

Automated coverage checks unreachable startup, recovery, stale lifecycle
responses, command gating, uncertain unlock outcomes and abort signaling/client
reuse. Mock setup/Terminal previews do not establish real Wi-Fi recovery.
Physical power cycling, router loss/rejoin, native socket cancellation,
ecosystem recovery and iOS compilation require their own hardware/platform checks.
See [v1.9.2 release notes](releases/v1.9.2.md) for this version's actual results.

Connected-home changes sync from the door on each foreground LockLink client.
Codes are hidden when another client replaces the pairing window. A home removed
by one client disappears on the others; a failed mutation is never replayed.
Apple Home membership and LockLink app-key access are separate permissions.
