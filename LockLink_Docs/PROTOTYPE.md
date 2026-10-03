# Firmware and output boundaries

Version 2.2.0 is ESP32-C3 app-only firmware. Wi-Fi credentials are configured
privately for first installation; saved network data takes priority on updates.
No Matter/Bluetooth, home-controller commands, or network Terminal is included.

## Local API

- `GET /status`: online, device, firmware version, commanded state, mode, armed,
  physical_state_known=false, and bounded numeric health diagnostics.
- `GET /challenge`: one random nonce, valid for ten seconds and one attempt.
- `POST /unlock`: HMAC-SHA256 of `unlock:<nonce>` with the private app key in
  `X-LockLink-Nonce` / `X-LockLink-Signature` headers. Success acknowledges a
  0.5-second release; an active pulse returns HTTP 409 without extending it.

Eight outstanding challenges support independent phones. A full pool returns
HTTP 503 without replacing valid challenges. Invalid authentication returns
HTTP 401 and cannot operate a real relay. Firmware without a valid app key
leaves relay mode unarmed. LED-only testing can accept an unsigned pulse but
never configures the relay pin. Legacy Terminal routes return HTTP 404.

The relay output is GPIO4 HIGH at idle and LOW for a 0.5-second release; GPIO8
is the active-LOW indicator. The ESP timer returns the output to idle even if
HTTP blocks or Wi-Fi fails. HIGH can energize a HIGH-ON module, so output
inactivity does not imply coil off or a physically locked door.

The output latches idle before networking and never restores an old release
after boot. No automatic command replay exists. See [relay setup](RELAY_SETUP.md)
for the circuit-specific power-failure hazards.

This API belongs only on a trusted LAN. Relay browser access requires one
explicitly configured local origin. Do not expose port 80 publicly; the device
is not a cloud/remote access service. Native widgets use the same signed API.

See [USB health](USB_DIAGNOSTICS.md) and [offline recovery](OFFLINE_BEHAVIOR.md).
