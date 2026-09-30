# Firmware and output boundaries

`LockLink_IoT` is the single firmware for the Matter **Door Release** door lock
and the LockLink app. Wi-Fi is provisioned over BLE during Matter commissioning,
or seeded from optional private config credentials when no network is saved.
Both control routes share a one-second release controller. Matter Unlock starts
a pulse, Lock stops it early, and repeated Unlock does not extend it.

The local HTTP API remains intentionally small:

- `GET /status` → `{"online":true,"device":"LockLink","state":"locked","mode":"led","armed":true,"matter_accessory":"door_lock","physical_state_known":false}`
- `POST /unlock` in LED mode → `{"success":true,"state":"unlocking","duration_ms":1000}`
- Repeated `POST /unlock` during a pulse → HTTP 409.

In relay mode, status reports `"mode":"relay"` and `armed` indicates whether
the private key is valid. `GET /challenge` returns a random nonce. The app
signs `unlock:<nonce>` with HMAC-SHA256 using the pairing key, then sends
`POST /unlock` with `X-LockLink-Nonce` and `X-LockLink-Signature` headers.
The ESP32 accepts a challenge once, for at most ten seconds. Requests without
a valid signature return HTTP 401 and cannot actuate the relay.
Each endpoint holds up to eight outstanding challenges. A full pool returns
HTTP 503 without replacing live challenges; unlock and terminal challenges use
separate pools. An unknown nonce does not invalidate another client's challenge.

The authenticated `/terminal/challenge` and `POST /terminal` routes support logs,
setup and connected-home management in both LED and relay modes. They always
require a configured firmware key. See the [terminal contract](TERMINAL_PLAN.md).

The output logic lives in `LockLink_IoT/src/release_output.cpp`. The default
driver uses GPIO4 with HIGH at idle and LOW during release, and GPIO8 for the
active-LOW blue LED on ESP32-C3 Super Mini. The ESP timer restores GPIO4 HIGH
and switches the LED off independently of network handling, even if Wi-Fi drops.
HIGH at idle energizes a HIGH-ON physical module; signal inactivity is not a
coil-OFF guarantee. There is no RGB
LED driver. Optional LED mode never configures or writes the relay pin. See
[relay setup](RELAY_SETUP.md) for the physical wiring and pairing steps.

LED mode allows cross-origin browser requests on a trusted local network.
Relay mode requires a signed, single-use challenge for every unlock and
restricts browser origins to one explicitly configured local origin. Neither
mode should be exposed to the public internet.

The public configuration starts in relay mode with an empty app signing key,
so its relay is unarmed. Set `LOCKLINK_RELAY_ENABLED 0` for a disconnected-relay
LED test; set it back to `1` and configure the key before installation.
Keep local keys and pin overrides in `LockLink_IoT/include/private_config.h`.
An invalid or missing key leaves relay mode unarmed for both Matter and app
commands. The app's saved key and the Matter commissioning code are different
credentials and must not be published.

USB `STATUS` reports Matter pairing, Wi-Fi, the app IPv4 address and whether
the release is active. `PAIR` displays setup information; `RESET MATTER`
deliberately clears Matter pairing/network settings. The status field `locked`
and Matter Locked both mean the output is inactive; neither verifies the latch
or door position. See [Matter setup](MATTER_SETUP.md) for pairing, recovery
and physical test requirements.
