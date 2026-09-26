# Apple Home, Google Home, and Alexa

The single `LockLink_IoT` firmware exposes **Door Release**, a momentary
Matter switch/outlet, alongside the existing LockLink app HTTP API.
Turn it **On** to release the door for two seconds; it automatically returns
to **Off**. Turning it Off early ends the release. Repeated On commands during
a release do not extend it. Use **"turn on Door Release"**, not "unlock door".

This is the user's selected switch behavior, not a Matter Door Lock accessory.
It does not ask for a door-lock voice PIN. Pairing still authenticates
controllers. Anyone with permission to operate the switch, including through
a linked voice assistant or automation, can release the door. Being connected
to the same Wi-Fi does not identify the owner. Avoid adding Door Release to
general All On scenes or unrelated routines.

Off means the release output is inactive. There is no sensor confirming that
the door closed or the latch engaged. This does not implement Apple Wallet
Home Key, NFC unlocking, or remote access for the LockLink app.

## Shared state across the app and assistants

The ESP32 owns one release state. An On command from Apple Home, Google Home,
Alexa, or the LockLink app starts the same output timer. Off from a Matter
controller stops that output early. The ESP32 reports the resulting On/Off
state to its paired Matter controllers, including after automatic shutoff.

On the active LockLink home screen, the app reads this same state 500 ms after
each completed status request. It also refreshes when you return from the
background or device settings. It follows the device after an app command
instead of displaying an independent two-second countdown. Slow requests do
not overlap; offline retries wait five seconds. Commands are never retried
automatically.

This synchronizes the release output, not room names, accessory names, scenes,
or routines. Add/share the same accessory with each Matter ecosystem using the
steps below. Each platform controls how quickly it displays reported changes;
network delays can cause a brief release to be missed. Background phone
widgets follow operating-system refresh limits and are not live indicators.
Without a sensor, no screen can confirm the door is physically closed or locked.

To check after installing the new firmware and app: keep LockLink open, turn
Door Release On in a paired Home app or with voice, and check that LockLink
shows the release then returns to idle. Repeat with the LockLink button while
watching the Home tile. Finally, turn the Home tile Off during a release and
confirm the output and app stop early. Repeat for each paired ecosystem.

## What is required

| Control route | Requirement |
| --- | --- |
| Apple Home locally | iPhone with iOS 18 or later; no home hub required for Wi-Fi Matter |
| Siri on iPhone | Accessory paired to Apple Home; verify the voice command on the phone |
| Google Home / Assistant | Compatible Google Matter hub plus development VID/PID configuration |
| Alexa | Compatible Matter-enabled Echo/eero controller; verify development accessory pairing |
| LockLink Android/iPhone app | Same local network, saved device address and app pairing key |

No integration subscription, Firebase service, AWS backend, or paid Apple
Developer membership is required by this firmware. The Google/Alexa apps alone
do not replace their Matter controllers. The user currently owns neither
controller, so those routes cannot be tested with the current hardware.
Apple's [hub-free support](https://support.apple.com/en-us/102135) is local;
a home hub can enable remote access later.
Voice processing may depend on the assistant's Internet service.

## Build and configure

The `LockLink_IoT/` project uses one environment, `esp32-s3-n16r8`, pinned to
pioarduino 55.03.312-1 with Arduino-ESP32 3.3.12 and its bundled ESP-Matter SDK.
Matter and the app API run together and share the output controller.

1. Install PlatformIO Core, then open a terminal in `LockLink_IoT/`.
2. Copy `include/private_config.example.h` to `include/private_config.h` only
   if it does not exist; preserve existing private keys and pin settings.
   This file is ignored by Git. Start with `LOCKLINK_RELAY_ENABLED 0` to test
   the board LED. The default board LED is GPIO 48; revision 1.1 boards may
   need `LOCKLINK_INDICATOR_GPIO 38` in the private configuration.
3. For the real relay, follow [the wiring guide](RELAY_SETUP.md), set
   `LOCKLINK_RELAY_ENABLED 1`, and confirm `LOCKLINK_RELAY_GPIO`. The active-HIGH
   driver powers the lock to **unlock**, not to lock.
4. Configure a strong, 64-character hexadecimal `LOCKLINK_UNLOCK_KEY_HEX` for
   the app. Generate one locally with
   `python -c "import secrets; print(secrets.token_hex(32))"`. Save that same
   hex value in the app once. The key is stored and used automatically; there
   is no password prompt per release. Relay mode remains disabled if this key
   is missing or malformed. Do not post the key in an issue or screenshot.
5. Run `pio run -e esp32-s3-n16r8`. When ready to install on the board, run
   `pio run -e esp32-s3-n16r8 -t upload`, then `pio device monitor -b 115200`.
   Close other serial monitors before uploading.

Wi-Fi is supplied over BLE during Matter pairing and saved by the Matter
stack. Do not run a second Wi-Fi manager or hard-code a different network.
The project keeps the Matter partition layout, so an ordinary update from a
previous Matter build should preserve pairing. Moving from older, non-Matter
firmware changes the partition layout; preserve private configuration first
and diagnose any commissioning problem before choosing a reset or flash erase.

## Apple Home first

1. Enable Bluetooth on the iPhone and connect it to the home network. ESP32-S3
   uses 2.4 GHz Wi-Fi; the phone may use 5 GHz if both bands share the same LAN.
   Avoid guest/client-isolated networks. Local IPv6 and multicast/mDNS must
   work; public Internet IPv6 service is not required for local Matter traffic.
2. In the USB serial monitor, read the generated manual Matter pairing code.
   It is device-specific and persists across reboots. This is a one-time
   setup code, **not** the app's HMAC key and not a spoken unlock PIN.
3. Open **Home > + > Add Accessory**, use **More Options** / manual code entry,
   or scan the optional setup QR. Wording may vary by iOS version. The optional
   SDK QR URL contains the setup secret; prefer manual entry if you do not
   want to open an external QR webpage.
4. If an uncertified-accessory prompt offers **Add Anyway**, select it for
   your own development board. Apple's currently published
   [Matter OTA guide](https://developer.apple.com/accessories/Apple-Matter-OTA-User-Guide.pdf),
   dated **2026-02-12**, still explicitly documents this option. This is not
   a guarantee that incomplete firmware or every future iOS version will pair.
5. Assign the name **Door Release** and a room. It may appear with an outlet
   icon because it uses the standard On/Off Plug-in Unit type (0x010A).
6. Turn it On and check that the LED returns to Off after two seconds. Then
   try **"Siri, turn on Door Release."** Verify on each phone before connecting
   a real lock. Apple account permissions still apply; shared-home access
   between different Apple accounts must be checked without a home hub.

Apple Home operates independently of the Flutter iOS app: an unsigned IPA or
LiveContainer installation does not prevent firmware pairing through Home.
No claim is made that the firmware has already been tested on iOS 27.

## Google Home

1. Set up a compatible Google Matter hub on this LAN and account. Buying one
   is outside the no-additional-hardware Apple Home setup.
2. Create a Matter test integration in Google Home Developer Console using
   the **actual test VID and PID printed by this firmware**, and select the
   matching On/Off Plug-in Unit device type. Do not assume a random VID/PID
   will be accepted. Use an authorized developer/tester account on the phone.
3. For a device already paired to Apple Home, open that accessory's Matter
   pairing/sharing mode in the existing ecosystem and obtain a **fresh** code.
   Add the Matter device in Google Home with that code. Do not reset the board
   or reuse its initial setup code to add another ecosystem.
4. Test the tile and **"Hey Google, turn on Door Release."** The endpoint is a
   switch; this is not an implementation of Google's restricted door-lock
   voice-unlock command.

For first commissioning directly through Google, use the original setup code
instead. Follow Google's current development checklist if the test device is
rejected; registering a test VID/PID does not provide commercial certification.
See Google's [development requirements](https://developers.home.google.com/matter/get-started).

## Alexa

1. Set up a compatible Matter-enabled Echo/eero controller and the Alexa app.
   Check Amazon's [supported controllers](https://developer.amazon.com/docs/alexaplus/smarthome/matter-support.html).
2. Choose Add Device and the Matter device option. For first commissioning,
   use the board's setup code. For an already commissioned board, open pairing
   mode in an existing ecosystem and use its newly generated sharing code.
3. Add it as **Door Release** and test **"Alexa, turn on Door Release."**
   No custom AWS skill is needed for a standard Matter plug/switch. Development
   accessory acceptance and exact app prompts require testing on the actual
   controller; a compiled firmware is not proof of Alexa pairing.

## Existing LockLink app

After Wi-Fi commissioning, USB serial prints the current IPv4 address. Save
that address and the configured app key in LockLink. A DHCP reservation can
keep the address stable. The original `/status`, `/challenge`, and signed
`POST /unlock` routes are retained. Matter commands and app commands share the
same pulse controller. Never port-forward the ESP32's HTTP server.

The app's legacy `locked` status means release output inactive. The new status
response additionally reports `physical_state_known: false` and identifies the
Matter accessory as a momentary switch.

## Pairing information, reset, and recovery

Send `STATUS` followed by Enter over USB serial. It reports the current
commissioning, Wi-Fi, IP and local app-server state without printing setup
secrets. Wi-Fi connectivity and HTTP readiness are separate: Matter may have
joined the network before an IPv4 address is available for the app.

- `Matter: paired` means commissioning completed; `not paired` means add the
  accessory in Home or another supported controller.
- `Wi-Fi: connected` reports the Matter network connection.
- `App HTTP: http://<IPv4>` identifies the listening app server. A waiting
  message means it is not yet ready for local HTTP control.
- `Release: active` or `inactive` reports the release output, not door position.
- `Output: LED test` means only the board LED is used. `armed: no` in relay
  mode means the private app signing key is missing or invalid; commands cannot
  energize the relay until it is configured.

A single `ESP_ERR_WIFI_CONN` with “sta is connecting, return error” during
startup means another connection attempt was already running. It is not proof
of a lasting network failure. The supplied device log establishes successful
flashing and startup, but does not establish successful Home pairing or a
usable app connection. Check later `STATUS` output and the controller app.

If the error repeats and the board stays disconnected, check 2.4 GHz coverage,
router credentials and client isolation. If Wi-Fi is connected but there is no
IPv4 address, check DHCP on the router. If Matter is connected but the app is
offline, use the current IPv4 address, keep the phone on the same LAN, and
check `GET /status`. Matter owns the ESP-IDF network interface; the firmware
uses that interface for HTTP readiness instead of relying on Arduino's
separate `WiFi.status()` bookkeeping.

Send `PAIR` followed by Enter over USB serial to display setup information.
Once paired, additional ecosystems should use the existing platform's
pairing/sharing workflow. Multiple pairings can coexist without duplicate
relay controllers.

Send the exact line `RESET MATTER` over USB serial to deliberately clear Matter
pairings/Wi-Fi and restart commissioning. This first stops the release. The
app signing key remains in the firmware's private configuration. Remove stale
accessories from the home apps before pairing again. Use this only when you
intend to remove pairings and recommission, not as the first response to one
startup warning. A full flash erase also destroys stored pairing/network data
and is a deliberate last-resort recovery step.

For **No Response**, check power, the home network, client isolation, local
IPv6/mDNS, and whether the required ecosystem controller is online. USB setup
information is available without exposing it through an unauthenticated HTTP
endpoint. A firmware crash, reset, or power loss must leave the relay inactive;
retain the external signal pulldown described in the wiring guide.

## Validation boundaries

From `LockLink_IoT`, `python tools/test_native.py` exercises network readiness,
command timing, and the output wrapper with simulated interface/GPIO/timer
boundaries. `pio run` verifies compilation
and linking. Neither verifies Wi-Fi commissioning, Siri/Google/Alexa behavior,
relay wiring, or physical door operation. The supplied serial log confirms
flashing and startup only. Check commissioning/control in LED mode first, then
test the installed lock, including Wi-Fi loss during a release and reboot.

Check mixed app/Matter commands in LED mode: release from the app and immediately
send Matter Off; then send Matter On immediately after a pulse expires. These
must work even before the displayed switch state catches up. Repeated On must
not extend an active pulse, and pairing, identification, and reset must never
start one.

## Official references

- [Apple: hub-free Matter pairing and control](https://support.apple.com/en-us/102135)
- [Apple: Add Anyway in the Matter OTA guide](https://developer.apple.com/accessories/Apple-Matter-OTA-User-Guide.pdf)
- [Espressif: Matter library](https://docs.espressif.com/projects/arduino-esp32/en/latest/matter/matter.html)
- [Google: development prerequisites and test IDs](https://developers.home.google.com/matter/get-started)
- [Google: supported device types](https://developers.home.google.com/matter/supported-devices)
- [Alexa: Matter controller requirements](https://developer.amazon.com/docs/alexaplus/smarthome/matter-support.html)
