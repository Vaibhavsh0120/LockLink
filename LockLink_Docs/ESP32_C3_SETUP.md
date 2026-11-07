# ESP32-C3 Super Mini installation (v2.2.5)

## Hardware and behavior

| Item | Configuration |
| --- | --- |
| Board | [ESP32-C3 Super Mini](https://robu.in/product/esp32-c3-development-board-esp32-supermini/), 4 MB flash, no PSRAM |
| PlatformIO environment | `esp32-c3-supermini` |
| Relay module | [Single 3V Relay (SRD-DC03V-SL-C)](https://robu.in/product/single-3v-relay-isolated-drive-control-module/), high-level trigger, powered from 3.3 V |
| Relay signal | GPIO4; LOW at idle, HIGH during release (high-level trigger) |
| Release | 1.5 seconds; repeated commands do not extend it |
| Blue LED | GPIO8; LOW is ON, HIGH is OFF; follows the release timer |
| USB | Native USB Serial/JTAG, 115200 monitor; no connected computer required to run |

The [Super Mini manufacturer guide](https://www.nologo.tech/en/product/esp32/esp32c3SuperMini/esp32C3SuperMini.html)
documents its 4 MB flash and active-LOW GPIO8 LED. The base PlatformIO board is
`esp32-c3-devkitm-1`; the project overrides flash mode to DIO at 40 MHz and uses
the Super Mini's actual pins instead of that base board's RGB `LED_BUILTIN`.

Wire GPIO4 to the relay module's signal input (IN), with a common ground.
Power the relay module from the ESP32-C3's 3.3 V output (VCC). The relay is a
high-level trigger: LOW at idle and HIGH during a 1.5-second release.
For a boot bias matching idle, use **10 kΩ from GPIO4 to GND**,
so the pin stays LOW while high-impedance during reset.
Never pull an ESP32 GPIO up to 5 V. Firmware loads the idle latch before
enabling the driver. Follow [relay wiring](RELAY_SETUP.md) for contact selection.

With this high-level trigger relay, the module is de-energized at idle
and energizes during the 1.5-second release pulse. When ESP32 power is
lost, the relay de-energizes and the NO contact opens (fail-secure).

GPIO2/8/9 are boot strapping pins. GPIO8 is used only for the board's existing
LED. Do not move the relay to those pins or to USB/flash pins. Compile-time
checks reject the old S3 GPIO2/GPIO48 settings.

## Build and flash

1. Preserve `LockLink_IoT/include/private_config.h`. If absent, copy the example.
   Use `LOCKLINK_RELAY_GPIO 4`, `LOCKLINK_INDICATOR_GPIO 8`, and
   `LOCKLINK_RELAY_ENABLED 1`. Preserve Wi-Fi credentials and the app signing key.
2. A valid 64-character hexadecimal `LOCKLINK_UNLOCK_KEY_HEX` is required for
   real relay operation through the app. Save the same key in
   Settings on each phone. Use a unique private key for a real door, never the
   app's publicly shipped demo pairing value. Existing saved keys are retained;
   replace a demo key on both ends before installation. Public/CI builds with
   an empty key are deliberately unarmed.
3. From `LockLink_IoT`, run `pio run -e esp32-c3-supermini`, then
   `pio run -e esp32-c3-supermini -t upload` when ready to flash the C3.
   Close other serial monitors; add `--upload-port COMx` if needed.
4. Run `pio device monitor -b 115200`. USB `STATUS` must report v2.2.5,
   relay output and `armed: yes` after a configured build. First installation
   requires configured 2.4 GHz Wi-Fi credentials. Keep keys/private firmware private.

For a blue-LED-only first test, disconnect the relay and set
`LOCKLINK_RELAY_ENABLED 0`. This mode never writes GPIO4. Restore mode `1`,
rebuild and upload before the relay test. Disconnect the lock load until the
relay's idle polarity and 1.5-second cutoff have been verified.

If USB upload fails, hold BOOT, press/release RESET, then release BOOT to enter
the ROM downloader. Select its port and upload; press RESET afterward. Both
USB CDC and USB mode are enabled in the build. The application never waits for
a serial monitor before operating on standalone power.

## Migration and persistent state

The C3 image is RISC-V firmware for a new chip. Do not flash an S3 image to it.
Saved Wi-Fi does not automatically move between physical boards. Configure the
new C3's network and save its reported IP in LockLink. Version 2.2.0 has no
Matter/Bluetooth stack or smart-home provisioning. Remove the old accessory
from any home controllers you previously used; they can no longer control it.
The separate app signing key can remain the same if configured on both ends.
Fresh app installs default to `192.168.0.112`; existing saved addresses remain
unchanged. Reserve that address for the C3 in your router if appropriate, or
enter its actual reported IP. The app default does not set a static firmware IP.

The C3 uses a 4 MB partition table: 64 KB NVS for persistent Wi-Fi
settings, one 3,997,696-byte app slot, and a 64 KB crash dump partition. There is
no second OTA slot or filesystem; updates are by USB. A board previously
running the GPIO test sketch has a different partition layout. For that first
installation only, with the relay/load disconnected, erase **the C3** using
`pio run -e esp32-c3-supermini -t erase` before uploading this firmware.
Erasing deletes saved credentials. Once on this layout, ordinary
USB uploads preserve NVS; do not erase it for routine updates.

`firmware.factory.bin` spans the bootloader, partition table and app with
erased NVS between them. Use it only for first installation or deliberate
recovery: flashing that combined image wipes saved Wi-Fi and other NVS data.
Use `pio run -e esp32-c3-supermini -t upload` for ordinary updates that preserve
NVS, with the relay/load disconnected during firmware work.

## Before permanent installation

Verify GPIO4 is LOW at idle after cold boot, reset and power restoration,
and verify the actual lock/contact state. Test signed app
Unlock, repeated Unlock, Wi-Fi loss during a pulse,
and a new release immediately after expiry. GPIO4 must return LOW and the
blue LED must turn OFF after 1.5 seconds without needing a network response.
The relay de-energizes and NO opens when the pulse ends.
Check the actual charger/cable and circuit, including isolated widget-style
requests and occasional concurrent traffic. The requested bench sessions are
capped at 15 minutes; no endurance certification is implied. Check supply
stability and runtime memory while the local API is active: compile-time RAM
figures do not measure their peak heap use. Automated builds and simulated
tests cannot certify these physical results. Output status describes the
relay, not actual door position.
The [current investigation](RELIABILITY_2026-10-02.md) still has an unresolved
packet-loss failure. Do not treat v2.2.0 as validated for permanent installation.
