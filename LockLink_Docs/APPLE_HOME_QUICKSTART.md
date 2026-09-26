# Add your ESP32-S3 to Apple Home

Use `LockLink_Matter`, the new firmware. The original `LockLink_IoT` firmware
does not appear in Apple Home. Start with the relay disconnected and test the
onboard LED first.

## 1. Flash the board

Connect the ESP32-S3 by USB. On this Windows computer, open PowerShell and run:

```powershell
cd D:\_Root\Downloads\LockLink\LockLink_Matter
$pio = "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe"
& $pio run -e esp32-s3-matter -t upload
& $pio device monitor -b 115200
```

The default build uses the LED on GPIO 48, not the relay. If upload cannot pick
the USB port, add `--upload-port COMx` using your board's actual port.

Press the board's reset button after opening the monitor. Look for the **manual
Matter pairing code**. Keep it private. You can also type `PAIR` and press Enter
to show it while the device is unpaired.

## 2. Add it on your iPhone

1. Turn on Bluetooth and connect the iPhone to your home Wi-Fi.
2. Open **Home → + → Add Accessory**.
3. Choose **More Options** / manual setup-code entry and enter the code from
   the serial monitor. Exact wording can vary by iOS version.
4. If Home warns that the accessory is uncertified and offers **Add Anyway**,
   choose it for this personal development board.
5. Name it **Door Release** and choose a room.
6. Turn **Door Release On**. The board LED should turn on for two seconds,
   then turn off by itself.
7. Try **“Siri, turn on Door Release.”**

It appears as a switch/outlet, as requested. It does not show a verified locked
or unlocked door state. Apple's [current Matter guide](https://developer.apple.com/accessories/Apple-Matter-OTA-User-Guide.pdf)
documents Add Anyway; this firmware has not yet been paired on your iPhones.
Apple [supports local Wi-Fi Matter control on iOS 18+ without a home hub](https://support.apple.com/en-us/102135).

## 3. Enable the relay after the LED test

1. Copy `include/private_config.example.h` to `include/private_config.h`.
2. Set `LOCKLINK_RELAY_ENABLED` to `1` and confirm the relay GPIO and
   [wiring](RELAY_SETUP.md).
3. Generate a private app key with
   `python -c "import secrets; print(secrets.token_hex(32))"` and paste it into
   `LOCKLINK_UNLOCK_KEY_HEX`. Enter that same key once in LockLink's settings.
4. Close the serial monitor with Ctrl+C, then run the upload command again.
   Normal firmware updates preserve Matter pairing.
5. Test one two-second release, early Off, repeat On, Wi-Fi loss during a
   release, and reboot. The relay must never stay energized after the pulse.

The key is saved by the app; you do not enter a password each time. Matter uses
its own one-time pairing. Anyone permitted to operate Door Release can open
the door, including authorized voice controllers and automations.

## 4. Keep using the LockLink app

After pairing, serial output shows the ESP32's local IP address. Save that
address and the app key in LockLink. Both the center circle and **Unlock door**
perform the same action. Keep the phone and ESP32 on the same local network.

For the updated iPhone app, build a new IPA through the repository's macOS
release workflow or Xcode, then sideload it directly. Keep the **LockLinkWidgets**
extension when the installer asks; removing extensions removes the widget.
Open LockLink, save the device settings, and choose **Set up widgets**. Add
LockLink through the iPhone widget gallery. See [widget setup](WIDGETS.md) if
the installer cannot provision the shared storage permission.

Google Home and Alexa need compatible Matter controllers; their phone apps
alone are insufficient for this implementation. See [full Matter setup](MATTER_SETUP.md)
for controller requirements and adding more ecosystems with a fresh sharing code.
