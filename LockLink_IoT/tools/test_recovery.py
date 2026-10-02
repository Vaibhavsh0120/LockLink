"""Cycle this board's Wi-Fi over USB; no release, storage erase, or router changes."""
import argparse
import http.client
import json
from pathlib import Path
import time
import serial
from stress_device import Device


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--address", default="http://192.168.0.112")
    parser.add_argument("--cycles", type=int, default=5)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.cycles <= 20:
        parser.error("Use 1..20 cycles")
    device = Device(args.address, None)
    initial = device.status()["health"]
    port = serial.Serial()
    port.port, port.baudrate = args.port, 115200
    port.timeout, port.write_timeout = 0.1, 1
    port.dtr, port.rts = False, False
    results = []
    previous = initial["wifi_disconnects"]
    with port:
        for cycle in range(args.cycles):
            port.reset_input_buffer()
            started = time.monotonic()
            port.write(b"\nWIFI RECONNECT\n")
            time.sleep(0.3)
            while time.monotonic() - started < 45:
                try:
                    status = device.status()
                    health = status["health"]
                    if health["wifi_disconnects"] > previous:
                        assert health["boot"] == initial["boot"], "Reconnect restarted the board"
                        assert status["state"] == "locked", "Reconnect changed output state"
                        assert health["allocation_failures"] == 0, "Reconnect exhausted memory"
                        previous = health["wifi_disconnects"]
                        break
                except (OSError, ValueError, http.client.HTTPException):
                    pass
                time.sleep(0.2)
            else:
                raise AssertionError("Board did not recover after deliberate disconnect")
            results.append({"cycle": cycle + 1, "recovery_s": round(time.monotonic() - started, 2),
                            "disconnects": previous})
            print(json.dumps(results[-1]), flush=True)
            time.sleep(1)
    args.output.write_text(json.dumps({"reconnects": results}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
