# Relay setup for a 12 V power-to-unlock lock

The tested ESP32-S3 has its RGB indicator on GPIO 48. Relay mode uses **GPIO 2**
for the relay signal and keeps GPIO 48 as the pulse indicator. The relay is a
switch: the ESP32 GPIO must never power the 12 V lock directly.

## Choose the relay

The pictured Robu 5 V optocoupler board needs a 5 V relay supply. Its listing
does not clearly establish 3.3 V input compatibility or trigger polarity, so
do not connect its IN terminal straight to the ESP32 yet. A documented option
is **DFRobot DFR0473**: it accepts a 2.8–5.5 V supply and a high-level control
signal of at least 2.8 V, has COM/NO/NC contacts, and is rated for DC
switching. Verify the lock's peak current against the relay's *inductive*
load rating, not just the advertised resistive 10 A figure.

## Low-voltage wiring, after confirming the lock and supply ratings

For a power-to-unlock lock that remains locked without power:

```text
ESP32 GPIO 2  ---------------------- relay D / IN (active HIGH)
ESP32 GND     ---------------------- relay GND
regulated 3.3–5 V ------------------ relay VCC (per module specification)
10 kΩ resistor: GPIO 2 ------------ GND (keeps relay off during boot)

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

## Pair and enable

1. Copy `LockLink_IoT/include/private_config.example.h` to
   `include/private_config.h` if needed. The private file is gitignored.
2. Generate a random key with
   `python -c "import secrets; print(secrets.token_hex(32))"`.
   Put it in `LOCKLINK_UNLOCK_KEY_HEX`, and set
   `LOCKLINK_RELAY_ENABLED 1`. Keep GPIO 2 and active-HIGH for DFR0473.
3. Flash the firmware. Serial Monitor must report the relay output and must
   **not** say `Relay NOT armed`.
4. In the Android/iOS app, open device settings, enter the ESP32 local address
   and the same pairing key, then save. When the card says **Ready**, tapping
   Unlock sends a signed command and pulses the relay for two seconds.

An empty or invalid firmware key leaves the relay unarmed, even if relay mode
was enabled. The old unauthenticated LED command cannot actuate the relay.
An unlock request uses a fresh challenge and cannot be replayed. The native
app stores the key in secure storage; the web app keeps it only in memory.

For a browser hosted on the local network, set
`LOCKLINK_ALLOWED_WEB_ORIGIN` to the *exact* origin, including scheme and port
(for example `http://localhost:8080`). Its default empty value blocks web
unlock in relay mode. Do not set this to a public Vercel origin.

If ESP32 power fails, GPIO 2's pulldown and the normally open contact leave
this power-to-unlock lock unpowered. Wi-Fi loss disables new app commands;
an already started pulse still ends after two seconds. This software does not
measure lock position or prove that the door opened.
