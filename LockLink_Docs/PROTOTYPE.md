# Prototype boundaries

The initial API is intentionally small:

- `GET /status` → `{"online":true,"device":"LockLink","state":"locked","mode":"led","armed":true}`
- `POST /unlock` in LED mode → `{"success":true,"state":"unlocking","duration_ms":2000}`
- Repeated `POST /unlock` during a pulse → HTTP 409.

In relay mode, status reports `"mode":"relay"` and `armed` indicates whether
the private key is valid. `GET /challenge` returns a random nonce. The app
signs `unlock:<nonce>` with HMAC-SHA256 using the pairing key, then sends
`POST /unlock` with `X-LockLink-Nonce` and `X-LockLink-Signature` headers.
The ESP32 accepts a challenge once, for at most ten seconds. Requests without
a valid signature return HTTP 401 and cannot actuate the relay.

The output logic lives in `LockLink_IoT/src/lock_output.cpp`. The default
driver uses the onboard addressable RGB LED on GPIO 48. Explicit relay mode
drives GPIO 2 while the RGB LED stays an indicator. A nonblocking `millis()`
timer ends the pulse even if Wi-Fi drops. See
[relay setup](RELAY_SETUP.md) for the physical wiring and pairing steps.

LED mode allows cross-origin browser requests on a trusted local network.
Relay mode requires a signed, single-use challenge for every unlock and
restricts browser origins to one explicitly configured local origin. Neither
mode should be exposed to the public internet.
