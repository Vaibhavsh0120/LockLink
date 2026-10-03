# Device offline and recovery (v2.2.2)

Offline means the app could not obtain a valid reply. It cannot distinguish
power loss, blocked traffic, a changed address, a stalled socket, or a radio
problem from that message alone. The red power LED only shows some power is
present. Output status is not physical door-position feedback.

## App behavior

Foreground Home waits 500 ms after each completed status read. Reads never
overlap and each has a four-second total deadline, including body reads. After
a transport failure it waits one second, then two seconds, then five seconds
between retries. Background and Settings pause polling. On return, control
waits for a fresh response; stale responses cannot restore online state.

Four installed apps do not create four constant connections. Four foreground
apps do poll independently and hold separate one-use challenges. The firmware
supports eight live unlock challenges; it returns busy rather than invalidating
someone else's nonce when full. Challenge preparation never opens the door.

Unlock is disabled when offline, unarmed, or already releasing. A lost command
reply produces an uncertain-result message and is never retried automatically.
Widgets also validate status and refuse to replay an uncertain release.

## Firmware recovery

Version 2.2.0 removes Matter/Bluetooth and app Terminal, including its retained
logs and second challenge pool. There are only status, challenge, and unlock
routes. USB-only diagnostics retain no history.

One ESP-IDF Wi-Fi owner reuses saved credentials, seeding private configuration
only if none exist. It retries an unavailable link after 5, 10, 20, then 30
seconds, capped at 30 seconds. Association without an IPv4 address is recovered
after a bounded DHCP wait. Recovery never erases storage or issues a release.
HTTP sockets restart on link events and DHCP address changes. The powered board
disables modem sleep and reapplies it after reconnecting.

The HTTP library is a project-local copy of the pinned Arduino implementation
with bounded idle/header/body waits, allocations, header/URI sizes, and explicit
socket close. The main loop has an eight-second watchdog. The 0.5-second release
cutoff runs in the ESP timer task, independently of HTTP and Wi-Fi.

## Checks when offline

1. Keep a manual way to enter/exit. Do not depend on this prototype as the sole
   access or emergency exit mechanism.
2. Check power and cable first. A healthy USB-powered bench does not prove the
   charger/cable or relay/lock supply is healthy at the door.
3. Confirm the phone is on the same LAN, not an isolated guest network/VPN.
4. Read USB `STATUS`: IP, signal, heap failures/minimum, uptime/reset reason,
   temperature, and disconnect count help separate failure types.
5. Update Settings if DHCP assigned a new address, and reserve the device's
   address on the router. The app default does not set a static board address.
6. USB `WIFI RECONNECT` tests only this board's recovery without wiping settings.
   For first installation, supply Wi-Fi in private firmware configuration;
   Bluetooth provisioning is no longer available.

A high minimum-heap margin and zero failed allocations rule out exhaustion in
that measured run, not every possible future fault. Chip temperature is not
ambient, regulator, or charger temperature. Do not diagnose overheating from
the power LED alone.

## Verification

See [v2.2.2 release notes](releases/v2.2.2.md) for completed checks and limitations.
The [2026-10-01 diagnosis](CONNECTION_DIAGNOSIS_2026-10-01.md) remains historical
evidence for the older memory-pressure failure, not a description of this build.
The installed charger, cable, physical relay/lock, metal-pipe placement, actual
phones and router loss/rejoin remain separate hardware acceptance checks. The
requested bench-test limit is 15 minutes, not a 24-hour endurance run. See the
[2026-10-02 investigation](RELIABILITY_2026-10-02.md) for the unresolved packet loss.
No short bench run can guarantee the device never goes offline.
