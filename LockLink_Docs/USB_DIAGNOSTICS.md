# USB health diagnostics (v2.2.3)

Open a USB serial monitor at 115200 baud and enter `STATUS` followed by Enter.
It reports the version, IP, association, signal, modem sleep, uptime, current
and minimum heap, largest allocation, allocation failures, reset reason,
Wi-Fi disconnect count/reason, chip temperature and peak, loop gap, stack
headroom, and commanded output state. No credentials are printed.

`WIFI RECONNECT` deliberately cycles only this board's Wi-Fi connection. It
does not erase settings, reboot, or release the output. Use it over USB to
check reconnect behavior. Unknown/overlong commands cannot operate the relay.

There is no app Terminal, network command route, pairing command, or retained
log history. `/status` carries bounded numeric health data on the trusted LAN.
The internal temperature reading is chip temperature, not charger, regulator,
enclosure, or ambient temperature. A steady power LED does not prove Wi-Fi or
the main loop is working.

From `LockLink_IoT`:

```powershell
python tools/serial_diagnostics.py --port COM7
python tools/serial_diagnostics.py --port COM7 --flood-seconds 5
python tools/stress_device.py --minutes 15 --clients 4 --incomplete-peers --output C:\temp\locklink-soak.json
```

The soak is read-only by default. On a physically isolated board only, add
`--release-cycles 20 --isolated-output` for authenticated GPIO/LED pulse tests.
These check reported cutoff, not actual pin timing or physical door movement.
No uncertain release command is retried. A completed zero-failure run is useful
evidence, not proof of permanent reliability. Interrupted checkpoints and failed
trials must not be reported as passing soaks. Keep private firmware/keys outside
published artifacts. See [v2.2.3 release notes](releases/v2.2.3.md).

`--minutes` is a total budget, capped at 15, including burst/probe/idle phases.
About 80% is available for continuous polling; the rest is reserved for checks.
All socket waits share the deadline. If checks cannot finish in that budget,
the report marks `budget_exhausted` and exits nonzero instead of claiming a pass.
