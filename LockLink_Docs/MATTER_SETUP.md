# Apple Home, Google Home, and Alexa

The v1.9.3 `LockLink_IoT` firmware exposes **Door Release** as a Matter
**Door Lock** accessory alongside the LockLink app HTTP API. **Unlock** starts
a two-second release; the output then turns off and reports **Locked**.
**Lock** ends an active release early. Repeated Unlock commands during a
release succeed without extending it. Unsupported cluster commands cannot
actuate the output.

Matter pairing authenticates controllers. Anyone a controller permits to
unlock the accessory, including through an authorized automation, can release
the door. Being connected to the same Wi-Fi does not identify the owner.
The firmware does not implement user PIN management; assistant authentication,
voice permissions and unsupported operations are controlled by each ecosystem.

Reported Locked means the release output is inactive. There is no sensor confirming that
the door closed or the latch engaged. This does not implement Apple Wallet
Home Key, NFC unlocking, or remote access for the LockLink app.

## Shared state across the app and assistants

The ESP32 owns one release state. An accepted Matter Unlock command or LockLink
app unlock starts the same output timer. Matter Lock stops that output early.
The ESP32 reports Unlocked while the output is active and Locked when inactive,
including after automatic shutoff. Attribute reporting itself never actuates
the output.

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

To check after installing the firmware and app: keep LockLink open, unlock
Door Release in a paired Home app, and check that LockLink
shows the release then returns to idle. Repeat with the LockLink button while
watching the Home tile. Finally, send Lock during a release and
confirm the output and app stop early. Repeat for each paired ecosystem.

## What is required

| Control route | Requirement |
| --- | --- |
| Apple Home locally | iPhone with iOS 18 or later; no home hub required for Wi-Fi Matter |
| Siri on iPhone | Accessory paired to Apple Home; verify unlock authentication and permissions on the phone |
| Google Home / Assistant | Compatible Google Matter hub plus development VID/PID configuration; voice unlock disabled |
| Alexa | Compatible Matter-enabled Echo/eero controller; verify development accessory acceptance and lock permissions |
| LockLink Android/iPhone app | Same local network, saved device address and app pairing key |

No integration subscription, Firebase service, AWS backend, or paid Apple
Developer membership is required by this firmware. The Google/Alexa apps alone
do not replace their Matter controllers. These routes need compatible hardware
and real-controller validation.
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

Wi-Fi can be supplied over BLE during Matter pairing, or configured with
`LOCKLINK_WIFI_SSID` and `LOCKLINK_WIFI_PASSWORD` in `include/private_config.h`.
The optional configured credentials are applied once at startup only if no
network or Matter pairing is saved and commissioning is not in progress.
They use Matter's own Wi-Fi driver; there is no second reconnect manager.
Saved credentials always take priority. The LockLink app can connect before
Home pairing when the board already has Wi-Fi and an IPv4 address.

Home does not need to stay open, and the phone does not need to remain nearby,
for the board to stay connected. Matter manages reconnects after a network
interruption. No firmware can guarantee connectivity during router/power
failure. Reserve the ESP32's IP address in the router if you want the app's
saved address to stay stable. Changing these config fields does not override
an existing saved network. Use the ecosystem's supported network-change flow,
or deliberately reset and pair again if changing networks; do not reset merely
because a connection briefly drops.

### Configured Wi-Fi followed by Home pairing

| Situation | Expected behavior |
| --- | --- |
| Fresh board, configured SSID/password | Seeds the saved network once; the local app works after an IP address is assigned. |
| Add Apple Home while that network is connected | Matter adds the controller's pairing; the configured network is already known. Keep the phone on the same LAN. |
| App and Home both send commands | Both use the same output controller; repeated Unlock does not extend the pulse. |
| Successful supported network change through a controller | Matter owns the new saved network; config values do not overwrite it on reboot. The app address may need updating. |
| Phone is on a different isolated network | Direct local app control cannot reach the ESP32. Pair/control on the same LAN. |
| Router temporarily unavailable | Matter retries the saved network; config is not repeatedly reapplied and pairings are not erased. |

Home pairing and Wi-Fi association are separate. The board has one Wi-Fi
station connection, with multiple authorized control paths over it. A network
change or pairing operation can interrupt connectivity; uninterrupted control
during setup is not guaranteed. This build's Matter Wi-Fi driver stores one
network, so it is not a roaming list or automatic alternate-router fallback.
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
5. Assign the name **Door Release** and a room. It uses the standard Door Lock
   device type and Door Lock cluster.
6. Unlock it and check that the LED turns off after two seconds. Then test
   **"Siri, unlock Door Release"** and any authentication the phone requires.
   Verify on each phone before connecting a real lock. Apple account permissions still apply; shared-home access
   between different Apple accounts must be checked without a home hub.

Apple Home operates independently of the Flutter iOS app: an unsigned IPA or
LiveContainer installation does not prevent firmware pairing through Home.
Pairing and assistant behavior need validation on the installed iOS version.

## Google Home

1. Set up a compatible Google Matter hub on this LAN and account. Buying one
   is outside the no-additional-hardware Apple Home setup.
2. Create a Matter test integration in Google Home Developer Console using
   the **actual test VID and PID printed by this firmware**, and select the
   matching Door Lock device type. Do not assume a random VID/PID
   will be accepted. Use an authorized developer/tester account on the phone.
3. For a device already paired to Apple Home, open that accessory's Matter
   pairing/sharing mode in the existing ecosystem, or use LockLink's **Add home app**,
   and obtain a **fresh** code.
   Add the Matter device in Google Home with that code. Do not reset the board
   or reuse its initial setup code to add another ecosystem.
4. Test the available lock controls. Google's [Door Lock restrictions](https://developers.home.google.com/matter/supported-devices#door-locks)
   disable voice unlocking. Remote unlock is also disabled across Google
   surfaces for Matter locks that do not require a PIN; this firmware does not
   implement mandatory user PINs. Do not promise Google unlock availability
   from successful commissioning alone.

For first commissioning directly through Google, use the original setup code
instead. Follow Google's current development checklist if the test device is
rejected; registering a test VID/PID does not provide commercial certification.
See Google's [development requirements](https://developers.home.google.com/matter/get-started).

## Alexa

1. Set up a compatible Matter-enabled Echo/eero controller and the Alexa app.
   Check Amazon's [supported controllers](https://developer.amazon.com/docs/alexaplus/smarthome/matter-support.html).
2. Choose Add Device and the Matter device option. For first commissioning,
   use the board's setup code. For an already commissioned board, open pairing
   mode in an existing ecosystem or LockLink's **Add home app**, and use the fresh code.
3. Add it as **Door Release** and test the available lock controls. Alexa's
   door-lock unlock permissions and authentication require controller testing;
   no PIN-free voice unlocking is promised. No custom AWS skill is needed for
   direct Matter pairing. Development
   accessory acceptance and exact app prompts require testing on the actual
   controller; a compiled firmware is not proof of Alexa pairing.

## Existing LockLink app

### Open the home app from LockLink

Each ecosystem guide has an **Open Apple Home**, **Open Google Home**, or
**Open Amazon Alexa** button. Obtain the setup/sharing code first.

- **Google on Android:** with a live QR payload, LockLink uses Google's
  [documented Matter intent](https://developers.home.google.com/samples/intent-based-commissioning)
  to open the Play Services commissioning/app picker. Select Google Home there.
  If that entry point is unavailable, LockLink opens Google Home for manual setup.
- **Apple Home on iPhone/iPad, Google Home on iOS, and Alexa:** open the installed
  app and follow the visible Add Accessory / Add Device steps. iOS URL schemes
  are best-effort app entry points, not a guaranteed accessory setup page; an app
  version or installation container can reject them. LockLink reports failure
  and keeps the manual instructions available. No HomeKit entitlement is added.
- **Android Apple Home and desktop/web:** the app-launch button is disabled;
  finish commissioning on a supported phone or iPad.

The Google Android QR handoff stays in memory and targets Play Services
explicitly. Other app launch URLs contain no pairing credentials. Returning
from an external app still requires a fresh ESP32 response before device actions
are enabled; the setup code is hidden when LockLink leaves the foreground.
Successful app launching does not prove accessory pairing. Check pairing
compares committed home IDs against the window-opening snapshot. Pending
commissioning, an existing legacy pairing, or a reboot cannot confirm a new home.

After Wi-Fi connects by either setup route, USB serial prints the current IPv4 address. Save
that address and the configured app key in LockLink. A DHCP reservation can
keep the address stable. The original `/status`, `/challenge`, and signed
`POST /unlock` routes are retained. Matter commands and app commands share the
same pulse controller. Never port-forward the ESP32's HTTP server.

The app's legacy `locked` status means release output inactive. The new status
response additionally reports `physical_state_known: false` and
`matter_accessory: "door_lock"`.

## Pairing information, reset, and recovery

`PAIR` reopens an expired first-home window with Bluetooth plus DNS-SD when BLE
is supported, matching its QR payload. The firmware keeps BLE memory after
commissioning so removing the last home does not require a reboot for Bluetooth
setup. This retains BLE RAM rather than returning it to the heap. Advertising
still follows SDK pairing windows; additional-home windows stay on the local
network. Validate memory headroom and re-pairing on the actual board/controllers.

Send `STATUS` followed by Enter over USB serial. It reports the firmware version,
commissioning, available IPv4 address and release-output state without printing setup
secrets. Wi-Fi connectivity and HTTP readiness are separate: Matter may have
joined the network before an IPv4 address is available for the app.

- `Matter: paired` means commissioning completed; `not paired` means add the
  accessory in Home or another supported controller.
- `Wi-Fi: <IPv4>` gives the current local address; `offline` means an active
  network with IPv4 is not available. The startup `Wi-Fi: connected` message
  alone does not establish IPv4 readiness.
- `LockLink app address: <IPv4>` is a startup log emitted when the HTTP server
  starts. `STATUS` does not probe that server; test `http://<IPv4>/status`.
- `Release: active` or `inactive` reports the release output, not door position.
- `Output: LED` means only the board LED is used. `armed: no` in relay
  mode means the private app signing key is missing or invalid; commands cannot
  energize the relay until it is configured.

A single `ESP_ERR_WIFI_CONN` with “sta is connecting, return error” during
startup means another connection attempt was already running. It is not proof
of a lasting network failure. A startup log alone does not establish successful
Home pairing or a usable app connection. Check later `STATUS` output and the controller app.

If the error repeats and the board stays disconnected, check 2.4 GHz coverage,
router credentials and client isolation. If Wi-Fi is connected but there is no
IPv4 address, check DHCP on the router. If Matter is connected but the app is
offline, use the current IPv4 address, keep the phone on the same LAN, and
check `GET /status`. Matter owns the ESP-IDF network interface; the firmware
uses that interface for HTTP readiness instead of relying on Arduino's
separate `WiFi.status()` bookkeeping.

Send `PAIR` followed by Enter over USB serial to display setup information.
Once paired, use LockLink **Smart home setup → Add home app** for a fresh
5-minute sharing code, or use the existing platform's pairing/sharing workflow.
The connected-home list supports rename and individual removal without erasing
Wi-Fi or other homes. Multiple pairings coexist with one output controller.
Invited Apple Home users share a home pairing; individual phones and Apple
Accounts are not exposed by Matter's fabric table.

Send the exact line `RESET MATTER` over USB serial to deliberately clear Matter
pairings/Wi-Fi and restart commissioning. This first stops the release. The
app signing key remains in the firmware's private configuration. Remove stale
accessories from the home apps before pairing again. Use this only when you
intend to remove pairings and recommission, not as the first response to one
startup warning. A full flash erase also destroys stored pairing/network data
and is a deliberate last-resort recovery step.
If configured Wi-Fi credentials remain in the firmware, they can seed Wi-Fi
again after a reset. To reset into BLE-only setup, first build with both
`LOCKLINK_WIFI_SSID` and `LOCKLINK_WIFI_PASSWORD` empty.

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
relay wiring, or physical door operation. Check commissioning/control in LED mode first, then
test the installed lock, including Wi-Fi loss during a release and reboot.

Check mixed app/Matter commands in LED mode: release from the app and immediately
send Matter Lock; then send Matter Unlock immediately after a pulse expires. These
must work even before the displayed lock state catches up. Repeated Unlock must
not extend an active pulse, and pairing, identification, and reset must never
start one.

## Official references

- [Apple: hub-free Matter pairing and control](https://support.apple.com/en-us/102135)
- [Apple: Add Anyway in the Matter OTA guide](https://developer.apple.com/accessories/Apple-Matter-OTA-User-Guide.pdf)
- [Espressif: Matter library](https://docs.espressif.com/projects/arduino-esp32/en/latest/matter/matter.html)
- [Google: development prerequisites and test IDs](https://developers.home.google.com/matter/get-started)
- [Google: supported device types](https://developers.home.google.com/matter/supported-devices)
- [Alexa: Matter controller requirements](https://developer.amazon.com/docs/alexaplus/smarthome/matter-support.html)
