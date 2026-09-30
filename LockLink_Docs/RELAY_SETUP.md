# Relay setup for a 12 V power-to-unlock lock

The ESP32-C3 Super Mini configuration uses **GPIO4** for the active-HIGH relay
and GPIO8 for its active-LOW blue LED. HIGH energizes the relay; LOW is idle.
An accepted Unlock energizes it for **one second**. The relay is a
switch: the ESP32 GPIO must never power the 12 V lock directly.

## Choose the relay

The installed module was confirmed to turn ON when GPIO4 is HIGH. Keep that
polarity; an active-LOW replacement is incompatible with this configuration.
Use a relay input compatible with 3.3 V logic and the module's specified supply.
Verify the lock's peak current against the relay's *inductive*
load rating, not just the advertised resistive 10 A figure.

## Low-voltage wiring, after confirming the lock and supply ratings

For a power-to-unlock lock that remains locked without power:

```text
ESP32 GPIO4   ---------------------- relay D / IN (active HIGH)
ESP32 GND     ---------------------- relay GND
regulated 3.3–5 V ------------------ relay VCC (per module specification)
10 kΩ resistor: GPIO4 ------------- GND (keeps relay off during boot)

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
   `LockLink_IoT/include/private_config.h` only if it does not already exist.
   Preserve existing private settings; this file is gitignored. First test
   the LED with `LOCKLINK_RELAY_ENABLED 0` and follow the
   [Apple Home quickstart](APPLE_HOME_QUICKSTART.md) to provide Wi-Fi over BLE
   or with optional private config credentials.
2. The public example has an empty key. If a private key is not already
   configured, generate a random key with
   `python -c "import secrets; print(secrets.token_hex(32))"`.
   Put it in `LOCKLINK_UNLOCK_KEY_HEX` and app settings. Set
   `LOCKLINK_RELAY_ENABLED 1` (the default). Use GPIO4 and active HIGH.
3. In `LockLink_IoT`, run `pio run -e esp32-c3-supermini -t upload`, then
   `pio device monitor -b 115200`. Serial Monitor must report the relay output
   and `armed: yes`; it must **not** say `Relay NOT armed`. Type `STATUS` and
   Enter to check Wi-Fi and the local app address after connection.
4. In the Android/iOS app, open device settings, enter the ESP32 local address
   and the same pairing key, then save. When the card says **Ready**, tapping
   Unlock sends a signed command and pulses the relay for one second.

The app defaults to `192.168.0.112` and has no built-in pairing key. These app
settings do not configure the ESP32. Use its reported local address and your
private key; saved keys on existing installations are retained.
For a 4–64 character text pairing value, set `LOCKLINK_UNLOCK_KEY_HEX`
to its SHA-256 hex digest and enter the original text in the app. A 64-character
hex key is used directly, without hashing. Changing firmware configuration
requires rebuilding and flashing the ESP32; saving app settings does not
change the device's key or IP address.

An empty or invalid firmware key leaves the relay unarmed for both Matter and
app commands, even if relay mode was enabled. An unauthenticated LED command
cannot actuate the relay.
An unlock request uses a fresh challenge and cannot be replayed. The native
app stores the key in secure storage; the web app keeps it only in memory.

For a browser hosted on the local network, set
`LOCKLINK_ALLOWED_WEB_ORIGIN` to the *exact* origin, including scheme and port
(for example `http://localhost:8080`). Its default empty value blocks web
unlock in relay mode. Do not set this to a public Vercel origin.

If ESP32 power fails, GPIO4's pulldown and the normally open contact leave
this power-to-unlock lock unpowered. Wi-Fi loss disables new app commands;
an already started pulse still ends after one second. This software does not
measure lock position or prove that the door opened.

The same firmware also accepts authorized Matter door-lock commands: Unlock
starts the one-second pulse and Lock ends it early. Repeated Unlock and app unlock
requests during an active pulse must not extend it. Verify app unlock followed by
Matter Lock, a new release immediately after expiry, Wi-Fi loss during a pulse,
and reboot with the lock disconnected before testing the installed lock.
Anyone allowed to operate **Door Release** can release the door, including
through permitted controllers or automations. Assistant voice unlocking depends
on ecosystem authentication and lock policies. See [Matter setup](MATTER_SETUP.md)
for controller permissions and Google's unlock restrictions.
