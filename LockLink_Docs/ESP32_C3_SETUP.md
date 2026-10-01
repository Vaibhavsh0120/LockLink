# ESP32-C3 Super Mini installation (v2.1.0)

## Hardware and behavior

| Item | Configuration |
| --- | --- |
| Board | ESP32-C3 Super Mini, 4 MB flash, no PSRAM |
| PlatformIO environment | `esp32-c3-supermini` |
| Relay signal | GPIO4; HIGH at idle, LOW during release (inverted) |
| Release | One second; repeated commands do not extend it; Lock stops it early |
| Blue LED | GPIO8; LOW is ON, HIGH is OFF; follows the release timer |
| USB | Native USB Serial/JTAG, 115200 monitor; no connected computer required to run |

The [Super Mini manufacturer guide](https://www.nologo.tech/en/product/esp32/esp32c3SuperMini/esp32C3SuperMini.html)
documents its 4 MB flash and active-LOW GPIO8 LED. The base PlatformIO board is
`esp32-c3-devkitm-1`; the project overrides flash mode to DIO at 40 MHz and uses
the Super Mini's actual pins instead of that base board's RGB `LED_BUILTIN`.

Wire GPIO4 to the relay's 3.3 V compatible input, with a common ground.
The inverted signal is HIGH at idle and LOW during a one-second release.
For a boot bias matching idle, use **10 kΩ from GPIO4 to 3.3 V**, replacing
the old pulldown: the pin is high impedance before firmware sets it HIGH.
Never pull an ESP32 GPIO up to 5 V. Firmware loads the idle latch before
enabling the driver. Follow [relay wiring](RELAY_SETUP.md) for contact selection.

Your earlier HIGH-ON relay test means the physical relay is energized at idle
with this firmware and drops out during release. HIGH is not physical OFF for
that module. Verify lock/contact behavior before reconnecting the load.

GPIO2/8/9 are boot strapping pins. GPIO8 is used only for the board's existing
LED. Do not move the relay to those pins or to USB/flash pins. Compile-time
checks reject the old S3 GPIO2/GPIO48 settings.

## Build and flash

1. Preserve `LockLink_IoT/include/private_config.h`. If absent, copy the example.
   Use `LOCKLINK_RELAY_GPIO 4`, `LOCKLINK_INDICATOR_GPIO 8`, and
   `LOCKLINK_RELAY_ENABLED 1`. Preserve Wi-Fi credentials and the app signing key.
2. A valid 64-character hexadecimal `LOCKLINK_UNLOCK_KEY_HEX` is required for
   real relay operation through both Matter and the app. Save the same key in
   Settings on each phone, or ensure the firmware signing key matches the
   [app's default pairing value](../LockLink_App/README.md). Existing saved keys
   are retained. Public/CI builds with an empty key are deliberately unarmed.
3. From `LockLink_IoT`, run `pio run -e esp32-c3-supermini`, then
   `pio run -e esp32-c3-supermini -t upload` when ready to flash the C3.
   Close other serial monitors; add `--upload-port COMx` if needed.
4. Run `pio device monitor -b 115200`. USB `STATUS` must report v2.1.0,
   relay output and `armed: yes` after a configured build. Use `PAIR` for
   initial Matter setup. Keep all codes/keys and private firmware private.

For a blue-LED-only first test, disconnect the relay and set
`LOCKLINK_RELAY_ENABLED 0`. This mode never writes GPIO4. Restore mode `1`,
rebuild and upload before the relay test. Disconnect the lock load until the
relay's idle polarity and one-second cutoff have been verified.

If USB upload fails, hold BOOT, press/release RESET, then release BOOT to enter
the ROM downloader. Select its port and upload; press RESET afterward. Both
USB CDC and USB mode are enabled in the build. The application never waits for
a serial monitor before operating on standalone power.

## Migration and persistent state

The C3 image is RISC-V firmware for a new chip. Do not flash an S3 image to it.
The S3's Matter identity, homes, labels and saved Wi-Fi do not automatically
move to the C3. Remove the old accessory from each home app, commission the
new C3, add any additional homes, and save the new board's local IP in LockLink.
The separate app signing key can remain the same if configured on both ends.
Fresh app installs default to `192.168.0.112`; existing saved addresses remain
unchanged. Reserve that address for the C3 in your router if appropriate, or
enter its actual reported IP. The app default does not set a static firmware IP.

The C3 uses a 4 MB partition table: 64 KB NVS for persistent Matter/Wi-Fi
settings, one 3,997,696-byte app slot, and a 64 KB crash dump partition. There is
no second OTA slot or filesystem; updates are by USB. A board previously
running the GPIO test sketch has a different partition layout. For that first
installation only, with the relay/load disconnected, erase **the C3** using
`pio run -e esp32-c3-supermini -t erase` before uploading this firmware.
Erasing deletes saved credentials and pairings. Once on this layout, ordinary
USB uploads preserve NVS; do not erase it for routine updates.

`firmware.factory.bin` spans the bootloader, partition table and app with
erased NVS between them. Use it only for first installation or deliberate
recovery: flashing that combined image wipes saved Wi-Fi and Matter homes.
Use `pio run -e esp32-c3-supermini -t upload` for ordinary updates that preserve
NVS, with the relay/load disconnected during firmware work.

## Before permanent installation

Verify GPIO4 is HIGH at idle after cold boot, reset and power restoration,
and verify the actual lock/contact state. Test signed app
Unlock, Matter Unlock, early Lock, repeated Unlock, Wi-Fi loss during a pulse,
and a new release immediately after expiry. GPIO4 must return HIGH and the
blue LED must turn OFF after one second without needing a network response.
The HIGH-ON module then re-energizes; this is not a coil-OFF guarantee. Test removing the
last home and pairing again, adding another home, and synchronization from
two phones. Check supply stability and runtime memory while BLE commissioning
and the local API are active: compile-time RAM figures do not measure their
peak heap use. Automated builds and simulated tests cannot certify these
physical results. Output status describes the relay, not actual door position.
