# Add your ESP32-S3 to Apple Home

Use `LockLink_IoT`, the single firmware for Apple Home and the LockLink app.
Start with the relay disconnected and test the onboard LED first. If you
already have `include/private_config.h`, preserve it and check that
`LOCKLINK_RELAY_ENABLED` is `0` for the LED test. Otherwise copy the public
example to that private file. Choose either Wi-Fi setup route below.

**Option A: configure Wi-Fi before Home pairing.** In the ignored
`LockLink_IoT/include/private_config.h`, set:

```cpp
#define LOCKLINK_WIFI_SSID "Your 2.4 GHz Wi-Fi name"
#define LOCKLINK_WIFI_PASSWORD "Your Wi-Fi password"
```

On startup these values seed Matter's Wi-Fi driver only when there is no saved
network, no existing Matter pairing, and no pairing in progress. The app can
then work before Home pairing. The board retains Bluetooth pairing so you can
add it to Home later. Existing saved credentials take priority; editing these
fields does not replace an already saved network. Do not publish this private
file or firmware built with your credentials.

**Option B: leave both fields empty.** Keep your iPhone connected to your home
Wi-Fi and Bluetooth enabled. During Add Accessory, the Home setup process
passes the network credentials to the ESP32 over Bluetooth LE. Follow any
network/password prompt on the phone; do not put your router password in
`LOCKLINK_UNLOCK_KEY_HEX`. That field is a separate app authentication key.
Matter saves the Wi-Fi credentials on the board for subsequent restarts.

With Option B on a fresh board, complete Home pairing before connecting the LockLink app.
The app currently accepts the board's address and app key; it cannot send
Wi-Fi credentials to an unconfigured board. Until pairing supplies them,
`Wi-Fi: not connected` and no app IP address are expected. Normal commands
use Wi-Fi after setup; Bluetooth is only the initial setup transport here.
This follows Espressif's [Wi-Fi pairing over Bluetooth example](https://github.com/espressif/arduino-esp32/blob/master/libraries/Matter/examples/Commissioning/MatterCHIPoBLEWiFi/README.md).

## 1. Flash the board

Connect the ESP32-S3 by USB. On this Windows computer, open PowerShell and run:

```powershell
cd D:\_Root\Downloads\LockLink\LockLink_IoT
$pio = "$env:USERPROFILE\.platformio\penv\Scripts\pio.exe"
& $pio run -e esp32-s3-n16r8 -t upload
& $pio device monitor -b 115200
```

The public example uses the LED on GPIO 48. If upload cannot pick
the USB port, add `--upload-port COMx` using your board's actual port.

Press the board's reset button after opening the monitor. Look for the **manual
Matter pairing code**. Keep it private. You can also type `PAIR` and press Enter
to show it while the device is unpaired.

## 2. Add it on your iPhone

1. Turn on Bluetooth and connect the iPhone to your home Wi-Fi. The ESP32
   needs 2.4 GHz; avoid a guest network that isolates devices.
2. Open **Home → + → Add Accessory**.
3. Choose **More Options** / manual setup-code entry and enter the code from
   the serial monitor. Exact wording can vary by iOS version.
4. If Home warns that the accessory is uncertified and offers **Add Anyway**,
   choose it for this personal development board.
5. Name it **Door Release** and choose a room.
6. **Unlock Door Release**. The board LED should turn on for two seconds,
   then turn off by itself.
7. Test **“Siri, unlock Door Release”** and any authentication required on the phone.

The v1.9.3 firmware appears as a Matter door lock. Its Locked/Unlocked states
describe only the inactive/active release output; they do not verify the latch
or door position. Apple's [current Matter guide](https://developer.apple.com/accessories/Apple-Matter-OTA-User-Guide.pdf)
documents Add Anyway; actual pairing and Siri operation on your iPhones
still need to be verified.
Apple [supports local Wi-Fi Matter control on iOS 18+ without a home hub](https://support.apple.com/en-us/102135).

After pairing, type `STATUS` and press Enter in the USB monitor to check
commissioning, Wi-Fi and the app's local address. A single “sta is connecting”
warning at startup does not mean pairing failed. If connection errors continue
or Home says **No Response**, use the [diagnostic steps](MATTER_SETUP.md#pairing-information-reset-and-recovery)
before resetting anything.

## 3. Enable the relay after the LED test

1. Open `include/private_config.h` in `LockLink_IoT`. Copy the example only
   if this private file does not already exist.
2. Set `LOCKLINK_RELAY_ENABLED` to `1` and confirm the relay GPIO and
   [wiring](RELAY_SETUP.md).
3. If no private app key is configured, generate one with
   `python -c "import secrets; print(secrets.token_hex(32))"` and paste it into
   `LOCKLINK_UNLOCK_KEY_HEX`. Enter that same key once in LockLink's settings.
4. Close the serial monitor with Ctrl+C, then run the upload command again.
   Normal firmware updates with the same Matter partition layout preserve
   pairing; do not erase the flash for an ordinary update.
5. Test one two-second release, early Lock, repeated Unlock, Wi-Fi loss during a
   release, and reboot. The relay must never stay energized after the pulse.

The key is saved by the app; you do not enter a password each time. Matter uses
its own one-time pairing. Anyone permitted to operate Door Release can open
the door, including authorized controllers and automations. Voice unlocking
depends on the ecosystem's door-lock permissions; the firmware does not supply
user PIN management or bypass controller authentication.

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
Google disables Matter door-lock voice unlock and remote unlock for locks
without mandatory PINs; commissioning alone does not prove unlock availability.

## 5. Put Home on the Lock Screen

First confirm **Door Release** works inside Apple Home. A Lock Screen control
is different from a home hub; the ESP32 is an accessory, not a HomePod/Apple TV hub.

For the bottom-left button (normally the flashlight): unlock the iPhone,
touch and hold the Lock Screen, choose **Customize → Lock Screen**, remove
the left control with **−**, then tap **+**. Search for **Home** and choose
the available Home control. If it offers **Scene or Accessory**, choose
**Door Release**; otherwise the Home control opens the Home controls picker.
Tap **Done**. Names and available controls can vary with iOS.

You can also add a direct tile in **Control Center → + → Add a Control →
Home Scene or Accessory → Choose Scene or Accessory → Door Release**.
If by "left side" you mean the widget page reached by swiping right, add the
LockLink widget there using [widget setup](WIDGETS.md).

Apple documents [Lock Screen customization](https://support.apple.com/guide/iphone/create-a-custom-lock-screen-iph4d0e6c351/ios)
and [Home accessory controls](https://support.apple.com/guide/iphone/control-accessories-iph0a717a8fd/ios).
The phone may require authentication according to its settings. A
[HomePod or Apple TV home hub](https://support.apple.com/en-us/102557) is separate
hardware used for features such as remote Home access; adding an ESP32 does
not make it appear under Home Hubs & Bridges.

## Share, rename, or remove a connected home

In LockLink, open **Settings → Smart home setup**. Connected homes refresh from
this door on each phone. Use a home's menu to rename it or remove its pairing;
removing it retains Wi-Fi, other homes, and the LockLink app key. This also lets
you remove a leftover pairing when Apple Home still reports Already paired.
Choose **Add home app** to create a fresh 5-minute sharing code for another home.
Keep the phone and door on the same Wi-Fi. This requires the updated ESP32 firmware.

Your Apple devices signed into the same Apple Account with Home enabled in
[iCloud](https://support.apple.com/guide/icloud/set-up-home-mm772c91c96c/icloud)
share the Home configuration without individually pairing again. To give your
mother's separate account access to the same Home, [invite her in Home Settings](https://support.apple.com/en-gb/102386).
That is still one connected-home record. Apple manages the people in that home;
LockLink shows and manages homes rather than Apple Accounts or individual phones.
