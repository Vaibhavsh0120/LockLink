# Device offline and recovery (v2.1.0)

LockLink cannot tell a powered-off ESP32 from a wrong address, a different Wi-Fi
network, blocked local traffic, or a lost reply. It reports an unreachable device
and offers power, Wi-Fi and address checks. It never treats missing data as a
verified door position.

Home, Terminal, and smart-home setup show connection failures in red, including
the dark theme. Initial connection checking stays neutral. Read-only background
refreshes do not disable enabled pairing buttons; explicit commands and lost
connections do. A deliberate command may wait for one current poll, and is
discarded if that poll loses the device or detects a restart.

| Situation | Behavior and recovery |
| --- | --- |
| Device off or unreachable at app launch | Home shows Connecting during the first check and two quick recovery attempts, then Offline if still unreachable. Unlock, setup-code generation and Terminal commands stay disabled. Settings and guide navigation remain available. |
| Saved settings or secure storage cannot be read | Stop loading, keep control disabled, and offer Open Settings. Retry loading there; returning reloads the saved address and key, including after a partially failed save. |
| Wi-Fi disappears while the app is open | The next request fails or times out. Disable device actions, clear pairing secrets and any open QR dialog, and discard current setup metadata. Existing terminal logs stay readable. |
| Device comes back at the same address | Home retries status one second after the first transport failure, then after two seconds, then every five seconds. A brief loss shows Reconnecting and disables unlock immediately. Terminal/setup retain their five-second recovery interval. Restore actions after a fresh successful response. Never automatically resend PAIR or Unlock. |
| App returns from the background or Settings | Revalidate the connection before allowing control. Old responses cannot restore the previous online state or pairing secrets. |
| Unlock reply is lost | Report “No confirmation. Check the device before retrying.” The ESP32 may already have accepted the command; do not infer failure or send another automatically. |
| Router assigns another IP | Automatic reads keep using the saved address. Check the new address over USB/router and update Settings. LockLink does not scan the network automatically. |
| Device has never joined Wi-Fi | App Terminal cannot reach it. Power it on, open USB serial at 115200 baud and run `PAIR` to obtain the initial Matter code. Use that code for Bluetooth commissioning in the chosen home app, or connect using the configured firmware network. |
| Device is already in another home | Use LockLink Smart home setup → Add home app for a fresh sharing code, or use that home's Matter sharing flow. Do not use the initial code or reset the device to add another home. |
| Wrong app key or older firmware | Terminal/setup show a specific key or firmware error instead of repeatedly retrying it. Correct Settings or firmware, then retry. |

## Request and firmware behavior

Home displays a busy connection-check control during pending requests, including
automatic offline checks. Invalid device responses show an address/firmware
error immediately and use the five-second interval. Successful status responses
reset the quick-recovery sequence. Requests remain non-overlapping.

USB or authenticated Terminal `STATUS` also reports actual Wi-Fi association,
signal strength, modem sleep, uptime, free/minimum heap, largest free block,
allocation-failure count and the numeric ESP-IDF reset reason.
The ESP32-C3 retains only the latest 16 application log lines in RAM, keeping
history below 3 KB. These help distinguish poor reception, a disconnected radio
and a restart from an HTTP timeout without exposing network or pairing credentials.

Before Matter starts Wi-Fi, the firmware configures two static RX buffers and
four dynamic RX/TX buffers. AMPDU RX is disabled for this small memory budget.
Matter retains connection/reconnection ownership and BLE commissioning remains
available. Terminal checks log allocation before executing a command, and streams
the response through a fixed 256-byte JSON buffer instead of allocating another
complete response. A short socket write ends the response; it never replays a command.

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

On 2026-10-01, live checks of the USB-connected ESP32-C3 reproduced intermittent
HTTP connection timeouts. During one outage, the router answered eight of eight
pings while the ESP32 answered none; USB `STATUS` still responded, and the
device later recovered without a restart. Its reserved address matched the app.
This confirms a reachability problem but does not identify its cause.

After loading the diagnostic application image, signal readings ranged from
-53 to -66 dBm and modem sleep was off. Free heap dropped from roughly 16 KB to
8.5 KB during 20 status reads, then recovered after idle time. All 20 reads
succeeded. These readings do not establish a memory leak or prove that memory
pressure caused the earlier outage.

One authenticated unlock through `flutter run -d web-server` and a temporary
loopback-only proxy returned HTTP 200. USB logs recorded release active and
inactive exactly one second apart. This verifies command acceptance and the
firmware release interval; physical door movement was not measured. The proxy
was needed for the test browser's origin and does not change iPhone networking.

The subsequent cable comparison could not proceed: Windows reported a USB
power surge, the COM port disappeared, and device enumeration reported a USB
descriptor failure. Hardware testing was stopped and the user was asked to
unplug the board and isolate it from the attached relay. This is evidence of a
hardware/power fault during that cable change, not proof of its specific source
or of the cause of the earlier Wi-Fi outage.
The user reported powering the relay from the ESP32's 3.3 V pin. COM7 later
returned at another USB connection location. Relay voltage/current requirements
and bare-board isolation still need confirmation before further relay tests;
no claim about the correct relay supply voltage has been made.

Automated coverage checks unreachable startup, recovery, stale lifecycle
responses, command gating, uncertain unlock outcomes and abort signaling/client
reuse. Mock setup/Terminal previews do not establish real Wi-Fi recovery.
Physical power cycling, router loss/rejoin, native socket cancellation,
ecosystem recovery and iOS compilation require their own hardware/platform checks.
See [v2.1.0 release notes](releases/v2.1.0.md) for this version's actual results.

The user subsequently confirmed USB-only operation with the relay disconnected.
The outage still reproduced, and iPhone Safari also could not load `/status`.
Instrumented testing after reducing log history recorded 14 allocation failures
and a 244-byte lifetime heap minimum, confirming memory pressure rather than
establishing a memory leak. Adding bounded Wi-Fi buffers completed 376 HTTP
responses with zero allocation failures and a 1,772-byte lifetime minimum.
The user confirmed automatic connection/recovery on cold launch and foreground
return. These checks preserve Wi-Fi and Matter storage and send no diagnostic
release or pairing-changing commands. See the [connection diagnosis](CONNECTION_DIAGNOSIS_2026-10-01.md)
for the original outage, repair stages and final hardware results.
The final image, including checked Terminal JSON streaming, completed 376/376
requests over 316.6 seconds with no timeouts or allocation failures. Its reported
minimum heap was 4,964 bytes and final free heap 23,284 bytes. This verification
used USB power with the relay disconnected and did not test fresh commissioning
or a router outage.

Connected-home changes sync from the door on each foreground LockLink client.
Codes are hidden when another client replaces the pairing window. A home removed
by one client disappears on the others; a failed mutation is never replayed.
Apple Home membership and LockLink app-key access are separate permissions.
