# Relay setup for a 12 V power-to-unlock lock

The ESP32-C3 Super Mini uses **GPIO4 HIGH at idle and LOW for two seconds**
on an accepted Unlock. GPIO8 drives the active-LOW blue LED, on during the
pulse and off at idle. This is the inverted GPIO signal; it does not identify
whether a particular module's coil is energized. The relay is a
switch: the ESP32 GPIO must never power the 12 V lock directly.

## Choose the relay

The earlier module test confirmed that GPIO4 HIGH turns the relay ON.
With the inverted firmware, that module is **energized at idle** and drops
out for the two-second pulse. A LOW-ON module instead stays off at idle and
energizes during the pulse. Check coil and contact behavior with no lock load.

The old HIGH-pulse/NO-contact wiring is no longer valid for that HIGH-ON module:
its NO contact now supplies a power-to-unlock lock at idle. An NC contact could
supply the lock during the LOW pulse, but also when relay/controller power is
lost while lock power remains. Do not assume the old locked-on-power-loss
behavior survives this inversion. Confirm the intended circuit before
reconnecting the load.
Use a relay input compatible with 3.3 V logic and the module's specified supply.
Verify the lock's peak current against the relay's *inductive*
load rating, not just the advertised resistive 10 A figure.

## Low-voltage wiring, after confirming the lock and supply ratings

For a power-to-unlock lock with a **LOW-ON relay module**, the circuit is:

```text
ESP32 GPIO4   ---------------------- relay D / IN (LOW-ON module)
ESP32 GND     ---------------------- relay GND
regulated 3.3–5 V ------------------ relay VCC (per module specification)
10 kΩ resistor: GPIO4 ------------- 3.3 V (matches idle HIGH during boot)

12 V supply + -- suitable DC fuse -- relay COM
relay NO --------------------------- lock +
lock - ----------------------------- 12 V supply -
```

The 12 V supply and its mains wiring must be enclosed and installed safely.
Use the lock manufacturer's specified supply current, fuse, and any required
coil suppression; a DC coil may need a flyback diode across its terminals,
subject to the lock manufacturer's instructions. Keep 12 V and mains off the
ESP32 GPIO. Confirm that the manual key/button and required emergency exit
remain usable with the controller disconnected. Check relay contact state with
a meter and no lock connected before applying 12 V.

## Configure and enable

1. Copy `LockLink_IoT/include/private_config.example.h` to
   `LockLink_IoT/include/private_config.h` only if it does not already exist.
   Preserve existing private settings; this file is gitignored. First test
   LED with `LOCKLINK_RELAY_ENABLED 0` and configure Wi-Fi in the private file
   for first installation. A saved network takes priority on routine updates.
2. The public example has an empty key. If a private key is not already
   configured, generate a random key with
   `python -c "import secrets; print(secrets.token_hex(32))"`.
   Put it in `LOCKLINK_UNLOCK_KEY_HEX` and app settings. Set
   `LOCKLINK_RELAY_ENABLED 1` (the default). Use GPIO4: HIGH idle, LOW pulse.
3. In `LockLink_IoT`, run `pio run -e esp32-c3-supermini -t upload`, then
   `pio device monitor -b 115200`. Serial Monitor must report the relay output
   and `armed: yes`; it must **not** say `Relay NOT armed`. Type `STATUS` and
   Enter to check Wi-Fi and the local app address after connection.
4. In the Android/iOS app, open device settings, enter the ESP32 local address
   and the same pairing key, then save. When the card says **Ready**, tapping
   Unlock sends a signed command and pulls GPIO4 LOW for two seconds.

The app defaults to `192.168.0.112` and the pairing value documented in the
[app guide](../LockLink_App/README.md). Saved addresses and keys take priority.
These app defaults do not configure the ESP32; its reported local address and
configured signing key must match the app settings.
For a 4–64 character text pairing value, set `LOCKLINK_UNLOCK_KEY_HEX`
to its SHA-256 hex digest and enter the original text in the app. A 64-character
hex key is used directly, without hashing. Changing firmware configuration
requires rebuilding and flashing the ESP32; saving app settings does not
change the device's key or IP address.

The powered controller disables Wi-Fi modem sleep once its network is ready,
and reapplies this after reconnecting. This reduces network receive delays at
the cost of higher power consumption. Unlock still uses a fresh challenge and
signed command; the two-second pulse begins immediately after authentication.
The foreground app prepares one short-lived challenge while the output is
ready, so a tap with a fresh preparation needs only the signed command request.
It consumes that challenge once and falls back to fetching a fresh one when
needed. Preparation does not operate the relay or retry an uncertain command.
Router congestion, weak signal and phone networking can still add latency.

An empty or invalid firmware key leaves the relay unarmed for app commands,
even if relay mode was enabled. An unauthenticated LED command
cannot actuate the relay.
An unlock request uses a fresh challenge and cannot be replayed. The native
app stores the key in secure storage; the web app keeps it only in memory.

For a browser hosted on the local network, set
`LOCKLINK_ALLOWED_WEB_ORIGIN` to the *exact* origin, including scheme and port
(for example `http://localhost:8080`). Its default empty value blocks web
unlock in relay mode. Do not set this to a public Vercel origin.

Replace the old GPIO4 pulldown with a 10 kΩ pullup to **3.3 V**, not 5 V,
to match the HIGH idle signal during reset. This bias does not certify the
coil or lock state when power fails; test the actual module/contact circuit.
Wi-Fi loss disables new app commands; an already started pulse still returns
GPIO4 HIGH after two seconds. This software does not
measure lock position or prove that the door opened.

The firmware accepts only LockLink app/widget commands. Repeated requests during
an active pulse must not extend it. Verify a new release after expiry, Wi-Fi loss
during a pulse, and reboot with the lock disconnected before testing the installed
lock. Anyone with the shared private app key can release the door. Removing the
app from a phone does not revoke that key; rotate it on the device and remaining
phones when access must be revoked.
