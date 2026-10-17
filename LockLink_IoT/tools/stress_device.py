"""Local soak; output pulses require explicit confirmation of disconnected hardware."""
import argparse
import ctypes
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import hmac
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import statistics
import time
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]


class RunBudgetExceeded(TimeoutError):
    pass


class Device:
    def __init__(self, address, key):
        url = urlsplit(address)
        address_ip = ipaddress.ip_address(url.hostname)
        if (url.scheme != "http" or not address_ip.is_private or
                address_ip.is_unspecified or url.username or url.password or
                url.path not in ("", "/") or url.query or url.fragment):
            raise ValueError("Use a private local HTTP IPv4 address")
        self.host, self.port, self.key = url.hostname, url.port or 80, key
        self.deadline = None

    def remaining(self):
        if self.deadline is None:
            return 4
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise RunBudgetExceeded("Total test budget exhausted")
        return min(4, remaining)

    def wait(self, seconds):
        if self.deadline is None:
            time.sleep(seconds)
            return
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise RunBudgetExceeded("Total test budget exhausted")
        time.sleep(min(seconds, remaining))
        self.remaining()

    def request(self, path, body=None, headers=None):
        connection = http.client.HTTPConnection(self.host, self.port, timeout=self.remaining())
        started = time.monotonic()
        try:
            connection.connect()
            transport = connection.sock
            def remaining():
                budget = 4 - (time.monotonic() - started)
                if budget <= 0:
                    raise TimeoutError("Request deadline exceeded")
                transport.settimeout(min(budget, self.remaining()))
            remaining()
            connection.request("POST" if body is not None else "GET", path,
                               body=body, headers=headers or {})
            remaining()
            response = connection.getresponse()
            chunks, length = [], 0
            while length <= 16384 and not response.isclosed():
                remaining()
                chunk = response.read1(16385 - length)
                if not chunk:
                    break
                chunks.append(chunk)
                length += len(chunk)
            payload = b"".join(chunks)
            if len(payload) > 16384:
                raise ValueError("Response exceeded diagnostic size limit")
            if response.status != 200:
                raise ValueError(f"HTTP {response.status}")
            return json.loads(payload), round((time.monotonic() - started) * 1000, 1)
        finally:
            connection.close()

    def status(self):
        payload, duration = self.request("/status")
        if (payload.get("device") != "LockLink" or payload.get("online") is not True or
                payload.get("state") not in ("locked", "unlocking")):
            raise ValueError("Unexpected device response")
        # Keep only public diagnostics; never persist challenges or app keys.
        return {"latency_ms": duration, "firmware": payload.get("firmware_version"),
                "state": payload["state"], "armed": payload.get("armed"),
                "health": payload.get("health")}

    def release_cycle(self):
        # Leave time for all four requests and the independent output cutoff.
        if self.deadline is not None and self.deadline - time.monotonic() < 18:
            raise RunBudgetExceeded("Not enough time to verify an isolated pulse")
        current = self.status()
        if current["state"] != "locked" or current["armed"] is not True:
            raise ValueError("Output is not ready for an isolated pulse test")
        challenge, _ = self.request("/challenge")
        nonce = challenge["nonce"]
        if not isinstance(nonce, str) or not re.fullmatch(r"[0-9a-f]{32}", nonce):
            raise ValueError("Invalid release challenge")
        signature = hmac.new(self.key, f"unlock:{nonce}".encode(), hashlib.sha256).hexdigest()
        reply, duration = self.request("/unlock", "", {"X-LockLink-Nonce": nonce,
                                                       "X-LockLink-Signature": signature})
        if reply.get("success") is not True or reply.get("duration_ms") != 1000:
            raise ValueError("Unexpected release acknowledgement")
        self.wait(1.2)
        if self.status()["state"] != "locked":
            raise ValueError("Output remained active after its cutoff")
        return {"unlock_latency_ms": duration, "cutoff_checked": True}

    def diagnostics(self):
        status = self.status()
        values = status.get("health")
        if not isinstance(values, dict):
            raise ValueError("Firmware does not provide health diagnostics")
        return {**values, "latency_ms": status["latency_ms"]}

    def obstruct(self, payload=b""):
        # Keep one incomplete peer open while a real status request queues behind it.
        with socket.create_connection((self.host, self.port), timeout=self.remaining()) as peer:
            peer.settimeout(self.remaining())
            if payload:
                peer.sendall(payload)
            self.wait(0.2)
            return self.status()


def load_key(path):
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8")
    match = re.search(r'^\s*#define\s+LOCKLINK_UNLOCK_KEY_HEX\s+"([0-9a-fA-F]{64})"',
                      text, re.MULTILINE)
    if not match:
        raise ValueError("No valid diagnostic key in private config")
    return bytes.fromhex(match[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--address", default="http://192.168.0.112")
    parser.add_argument("--minutes", type=float, default=15,
                        help="Total budget for every phase, at most 15 minutes")
    parser.add_argument("--interval", type=float, default=0.5)
    parser.add_argument("--clients", type=int, choices=range(1, 5), default=3)
    parser.add_argument("--burst-rounds", type=int, default=100)
    parser.add_argument("--burst-clients", type=int, choices=range(1, 5),
                        help="Independent client count for the final burst phase")
    parser.add_argument("--release-cycles", type=int, default=0)
    parser.add_argument("--isolated-output", action="store_true",
                        help="Confirm that relay/door wiring is physically disconnected")
    parser.add_argument("--incomplete-peers", action="store_true",
                        help="Exercise idle/partial connections on an isolated board")
    parser.add_argument("--key-file", type=Path, default=ROOT / "include/private_config.h")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not 0.1 <= args.minutes <= 15 or not 0.05 <= args.interval <= 60:
        parser.error("Use 0.1..15 total minutes and 0.05..60 second interval")
    if not 1 <= args.burst_rounds <= 1000:
        parser.error("Use 1..1000 burst rounds")
    device = Device(args.address, load_key(args.key_file))
    burst_clients = args.burst_clients or args.clients
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if not 0 <= args.release_cycles <= 1000:
        parser.error("Use 0..1000 isolated release cycles")
    if args.release_cycles and (not args.isolated_output or not device.key):
        parser.error("Pulse tests need a diagnostic key and --isolated-output")
    started = time.monotonic()
    # Reserve a second for closing sockets and saving the final report.
    device.deadline = started + args.minutes * 60 - 1
    soak_deadline = started + (args.minutes * 60 - 1) * 0.8
    samples, diagnostics, failures, probes, releases = [], [], [], [], []

    def record(operation, kind):
        try:
            value = operation()
            value["elapsed_s"] = round(time.monotonic() - started, 1)
            return value
        except RunBudgetExceeded:
            raise
        except (OSError, ValueError, KeyError, http.client.HTTPException) as error:
            # Do not print HTTP bodies, requests, signatures or credentials.
            failure = {"phase": kind, "elapsed_s": round(time.monotonic() - started, 1),
                       "error": type(error).__name__}
            if isinstance(error, ValueError) and re.fullmatch(r"HTTP \d{3}", str(error)):
                failure["http_status"] = int(str(error)[5:])
            failures.append(failure)
            print("Failure " + json.dumps(failure), flush=True)
            return None

    def check_health():
        result = record(device.diagnostics, "diagnostics")
        if result:
            diagnostics.append(result)
            print("Health " + json.dumps(result), flush=True)

    check_health()
    next_diagnostic, next_progress = 30.0, 30.0
    release_interval = max(3, (soak_deadline - started) / max(1, args.release_cycles))
    next_release = release_interval / 2
    release_aborted = False
    budget_exhausted = False

    def phone():
        next_challenge = 0
        try:
            while time.monotonic() < soak_deadline:
                tick = time.monotonic()
                result = record(device.status, "phone_poll")
                if result:
                    samples.append(result)
                    if device.key and tick >= next_challenge:
                        # Mimic one prepared challenge per foreground app every 10s.
                        record(lambda: device.request("/challenge")[0], "phone_challenge")
                        next_challenge = time.monotonic() + 10.5
                device.wait(min(max(0, args.interval - (time.monotonic() - tick)),
                                max(0, soak_deadline - time.monotonic())))
        except RunBudgetExceeded:
            pass

    try:
        with ThreadPoolExecutor(max_workers=args.clients) as phones:
            workers = [phones.submit(phone) for _ in range(args.clients)]
            while time.monotonic() < soak_deadline:
                elapsed = time.monotonic() - started
                if elapsed >= next_diagnostic:
                    check_health()
                    next_diagnostic += 30
                if (args.release_cycles and len(releases) < args.release_cycles and
                        not release_aborted and elapsed >= next_release):
                    result = record(device.release_cycle, "release_cycle")
                    if result:
                        releases.append(result)
                    else:
                        release_aborted = True  # An uncertain command is never replayed.
                    next_release += release_interval
                if elapsed >= next_progress:
                    print(f"Soak {elapsed:.0f}s: {len(samples)} replies; {len(failures)} failures; "
                          f"{len(releases)} verified pulses", flush=True)
                    args.output.write_text(json.dumps({"checkpoint": True,
                        "elapsed_s": round(elapsed, 1), "valid_status_responses": len(samples),
                        "failure_count": len(failures), "failures": failures,
                        "diagnostics": diagnostics, "verified_release_cycles": len(releases),
                        "release_aborted": release_aborted}, indent=2), encoding="utf-8")
                    next_progress += 30
                device.wait(0.1)
            for worker in workers:
                worker.result()
        with ThreadPoolExecutor(max_workers=burst_clients) as pool:
            for round_number in range(args.burst_rounds):
                device.remaining()
                jobs = [("health_burst", device.diagnostics) if client == 0 and
                         round_number % 5 == 0 else ("burst", device.status)
                        for client in range(burst_clients)]
                for kind, future in [(kind, pool.submit(operation)) for kind, operation in jobs]:
                    result = record(future.result, kind)
                    if result:
                        if kind == "health_burst":
                            diagnostics.append(result)
                        else:
                            samples.append(result)
                if round_number % 20 == 0:
                    print(f"Burst {round_number + 1}/{args.burst_rounds}: {len(failures)} failures", flush=True)
        if args.incomplete_peers:
            for name, payload in (
                ("idle", b""),
                ("partial_header", b"GET /status HTTP/1.1\r\nHost: device\r\n"),
                ("partial_body", b"POST /unlock HTTP/1.1\r\nHost: device\r\n"
                 b"Content-Type: text/plain\r\nContent-Length: 6\r\n\r\nST"),
            ):
                result = record(lambda: device.obstruct(payload), name)
                probes.append({"probe": name, "result": result})
                device.wait(2)
                record(device.status, "probe_recovery")
        print("Idle recovery: waiting 30 seconds", flush=True)
        device.wait(30)
        check_health()
        result = record(device.status, "idle_recovery")
        if result:
            samples.append(result)
    except RunBudgetExceeded:
        budget_exhausted = True
        print("Total budget exhausted; incomplete phases are not a passing soak", flush=True)
    finally:
        durations = sorted(sample["latency_ms"] for sample in samples)
        boots = {item["boot"] for item in diagnostics if "boot" in item}
        health = [sample["health"] for sample in samples if isinstance(sample.get("health"), dict)]
        uptime_resets = sum(current["uptime_s"] + 5 < previous["uptime_s"]
                            for previous, current in zip(health, health[1:]))
        health_summary = {}
        for field in ("free_heap", "min_heap", "largest_block", "stack_min_bytes"):
            values = [item[field] for item in health if isinstance(item.get(field), (int, float))]
            if values:
                health_summary[field + "_lowest"] = min(values)
        for field in ("allocation_failures", "wifi_disconnects", "chip_temperature_c", "chip_peak_c",
                      "temperature_failures", "max_loop_gap_ms", "http_rejected", "http_timeouts"):
            values = [item[field] for item in health if isinstance(item.get(field), (int, float))]
            if values:
                health_summary[field + "_highest"] = max(values)
        summary = {"timestamp_utc": datetime.now(timezone.utc).isoformat(),
                   "duration_s": round(time.monotonic() - started, 1),
                   "budget_exhausted": budget_exhausted,
                   "valid_status_responses": len(samples), "failure_count": len(failures),
                   "boot_ids_seen": len(boots), "concurrent_clients": args.clients,
                   "burst_clients": burst_clients,
                   "verified_release_cycles": len(releases), "release_aborted": release_aborted,
                   "uptime_resets": uptime_resets, "health_summary": health_summary,
                   "median_ms": statistics.median(durations) if durations else None,
                   "p95_ms": durations[int((len(durations) - 1) * 0.95)] if durations else None,
                   "max_ms": max(durations) if durations else None,
                   "diagnostics": diagnostics, "probes": probes, "failures": failures,
                   "releases": releases}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({key: value for key, value in summary.items()
                          if key not in ("diagnostics", "failures", "releases")}), flush=True)
    return 1 if (budget_exhausted or failures or len(boots) != 1 or not samples or uptime_resets or
                 len(releases) != args.release_cycles or
                 health_summary.get("allocation_failures_highest", 0) > 0) else 0


if __name__ == "__main__":
    # Keep this host awake only for this test; never change its power plan.
    if os.name == "nt":
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)
    try:
        raise SystemExit(main())
    finally:
        if os.name == "nt":
            ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
