"""Live HTTP boundaries. Only reads and unsigned requests; never releases a relay."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import http.client
import json
import socket
import time
from pathlib import Path
from stress_device import Device


def response_code(peer, expected_origin=None):
    response = http.client.HTTPResponse(peer)
    response.begin()
    response.read(2048)
    code = response.status
    if expected_origin is not None:
        assert response.getheader("Access-Control-Allow-Origin") == expected_origin or (
            expected_origin == "" and response.getheader("Access-Control-Allow-Origin") is None
        ), "Browser origin allowlist did not match"
    response.close()
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--address", default="http://192.168.0.112")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    device = Device(args.address, None)
    initial = device.status()
    checks = []

    def check(name, data, expected, fragment=0, origin=None):
        started = time.monotonic()
        with socket.create_connection((device.host, device.port), timeout=4) as peer:
            peer.settimeout(4)
            if fragment:
                for offset in range(0, len(data), fragment):
                    peer.sendall(data[offset:offset + fragment])
                    time.sleep(0.015)
            else:
                peer.sendall(data)
            code = response_code(peer, origin)
        assert code == expected, f"{name}: HTTP {code}, expected {expected}"
        assert device.status()["state"] == "locked", "An unsigned probe changed output state"
        checks.append({"name": name, "http_status": code,
                       "duration_ms": round((time.monotonic() - started) * 1000, 1)})

    check("fragmented_status", b"GET /status HTTP/1.1\r\nHost: device\r\nConnection: close\r\n\r\n", 200, 3)
    check("fragmented_unsigned_body", b"POST /unlock HTTP/1.1\r\nHost: device\r\nContent-Length: 6\r\n\r\nSTATUS", 401, 3)
    check("android_empty_form_post", b"POST /unlock HTTP/1.1\r\nHost: device\r\n"
          b"Content-Type: application/x-www-form-urlencoded\r\nContent-Length: 0\r\n\r\n", 401)
    check("nonempty_form_refused", b"POST /unlock HTTP/1.1\r\nHost: device\r\n"
          b"Content-Type: application/x-www-form-urlencoded\r\nContent-Length: 3\r\n\r\nx=1", 413)
    check("multipart_refused", b"POST /unlock HTTP/1.1\r\nHost: device\r\n"
          b"Content-Type: multipart/form-data; boundary=test\r\nContent-Length: 0\r\n\r\n", 413)
    check("oversized_body", b"POST /unlock HTTP/1.1\r\nHost: device\r\nContent-Length: 129\r\n\r\n" + b"X" * 129, 413)
    check("huge_declared_body", b"POST /unlock HTTP/1.1\r\nHost: device\r\nContent-Length: 99999999999999999\r\n\r\n", 413)
    check("negative_length", b"POST /unlock HTTP/1.1\r\nHost: device\r\nContent-Length: -1\r\n\r\n", 400)
    check("duplicate_length", b"POST /unlock HTTP/1.1\r\nHost: device\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n", 400)
    check("chunked_refused", b"POST /unlock HTTP/1.1\r\nHost: device\r\nTransfer-Encoding: chunked\r\n\r\n", 400)
    check("long_target", b"GET /" + b"X" * 300 + b" HTTP/1.1\r\nHost: device\r\n\r\n", 414)
    check("long_header", b"GET /status HTTP/1.1\r\nX-Long: " + b"X" * 600 + b"\r\n\r\n", 431)
    check("many_headers", b"GET /status HTTP/1.1\r\n" + (b"X-Header: " + b"X" * 90 + b"\r\n") * 12 + b"\r\n", 431)
    check("removed_terminal", b"GET /terminal/challenge HTTP/1.1\r\nHost: device\r\n\r\n", 404)
    for origin in ("http://localhost:8765", "http://127.0.0.1:8765"):
        check("allowed_browser_origin", b"OPTIONS /unlock HTTP/1.1\r\nHost: device\r\nOrigin: " +
              origin.encode() + b"\r\n\r\n", 204, origin=origin)
    check("unlisted_browser_origin", b"OPTIONS /unlock HTTP/1.1\r\nHost: device\r\n"
          b"Origin: https://elsewhere.test\r\n\r\n", 204, origin="")
    # A trickling peer cannot extend the shared header deadline indefinitely.
    with socket.create_connection((device.host, device.port), timeout=4) as peer:
        peer.settimeout(4)
        peer.sendall(b"G")
        time.sleep(0.1)
        with ThreadPoolExecutor(max_workers=1) as pool:
            queued = pool.submit(device.status)
            for byte in b"ET /status ":
                try:
                    peer.sendall(bytes([byte]))
                except OSError:
                    break
                time.sleep(0.15)
            status = queued.result()
        assert status["latency_ms"] < 2000, "Trickle exceeded the absolute header deadline"
        checks.append({"name": "trickle_does_not_extend_deadline", "queued_status_ms": status["latency_ms"]})
    # A late CR without its LF shares the same absolute header budget.
    with socket.create_connection((device.host, device.port), timeout=4) as peer:
        peer.settimeout(4)
        peer.sendall(b"G")
        with ThreadPoolExecutor(max_workers=1) as pool:
            queued = pool.submit(device.status)
            time.sleep(0.8)
            peer.sendall(b"ET /status HTTP/1.1\r")
            status = queued.result()
        assert status["latency_ms"] < 1500, "A missing LF restarted the header deadline"
        checks.append({"name": "missing_lf_keeps_absolute_deadline", "queued_status_ms": status["latency_ms"]})
    final = device.status()
    assert initial["health"]["boot"] == final["health"]["boot"], "Board restarted during boundary tests"
    assert final["health"]["allocation_failures"] == 0, "Boundary tests exhausted memory"
    args.output.write_text(json.dumps({"checks": checks, "final_health": final["health"]}, indent=2), encoding="utf-8")
    print(json.dumps({"boundary_checks_passed": len(checks), "allocation_failures": 0}))


if __name__ == "__main__":
    main()
