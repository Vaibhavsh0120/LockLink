"""Read STATUS over USB without exposing startup pairing codes."""
import argparse
import json
import time
import serial
from stress_device import Device


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--address", default="http://192.168.0.112")
    parser.add_argument("--flood-seconds", type=float, default=0,
                        help="Send an overlong inert command to test bounded USB input")
    args = parser.parse_args()
    if not 0 <= args.flood_seconds <= 60:
        parser.error("Flood duration must be 0..60 seconds")
    port = serial.Serial()
    device = Device(args.address, None)
    initial = device.status()["health"]
    port.port, port.baudrate = args.port, 115200
    port.timeout, port.write_timeout = 0.2, 1
    port.dtr, port.rts = False, False
    allowed = ("LockLink v", "Wi-Fi:", "Wi-Fi link:", "Signal:", "Modem sleep:",
               "Uptime:", "Heap minimum:", "Allocation failures:", "Reset reason:",
               "Wi-Fi disconnects:", "Chip temperature:", "Temperature read failures:",
               "Loop max gap:", "Output:", "Release:", "Wi-Fi TX limit:", "Output failed",
               "Wi-Fi memory", "Memory allocation", "Chip temperature unavailable")
    with port:
        port.reset_input_buffer()
        written = 0
        http_checks, next_http = 0, 0
        deadline = time.monotonic() + args.flood_seconds
        while time.monotonic() < deadline:
            try:
                written += port.write(b"X" * 512)
            except serial.SerialTimeoutException:
                pass
            if port.in_waiting:
                port.read(port.in_waiting)
            if time.monotonic() >= next_http:
                status = device.status()
                assert status["health"]["boot"] == initial["boot"], "USB flood restarted the board"
                assert status["state"] == "locked", "USB flood changed the output"
                http_checks += 1
                next_http = time.monotonic() + 0.5
        if written:
            print(json.dumps({"inert_usb_bytes_sent": written, "http_checks_during_flood": http_checks}))
        deadline = time.monotonic() + 6
        next_status = 0
        found = False
        while time.monotonic() < deadline:
            if not found and time.monotonic() >= next_status:
                port.write(b"\nSTATUS\n")
                next_status = time.monotonic() + 1
            line = port.readline().decode(errors="replace").strip()
            if line.startswith(allowed):
                print(line, flush=True)
                found |= line.startswith("LockLink v")
        final = device.status()
        assert final["health"]["boot"] == initial["boot"], "USB diagnostics restarted the board"
        assert final["health"]["allocation_failures"] == 0, "USB diagnostics exhausted memory"
        return 0 if found else 1


if __name__ == "__main__":
    raise SystemExit(main())
