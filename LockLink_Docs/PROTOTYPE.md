# Prototype boundaries

The initial API is intentionally small:

- `GET /status` → `{"online":true,"device":"LockLink","state":"locked"}`
- `POST /unlock` → `{"success":true,"state":"unlocking","duration_ms":2000}`
- Repeated `POST /unlock` during a pulse → HTTP 409.

The output logic lives in `LockLink_IoT/src/lock_output.cpp`. The default
driver uses the onboard addressable RGB LED on GPIO 48; a digital GPIO driver
remains available for an external LED. It uses a
nonblocking `millis()` timer so the HTTP server keeps responding during a pulse.
Wi-Fi retry also uses a timer. Later hardware work can replace the body of
`LockOutput::setActive`, but that alone is **not** authorization to attach a
real lock: the prototype has no authentication, access control, encryption,
safe failure policy, or physical validation.

For the local web prototype, firmware allows cross-origin browser requests.
That is acceptable only for a test LED on a trusted Wi-Fi. Restrict origins
and add authentication before any physical door hardware is introduced.
