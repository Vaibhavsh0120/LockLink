"""Host-tool regressions; no board, credentials, or output commands are used."""
from concurrent.futures import Future
from contextlib import redirect_stdout, redirect_stderr
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch

import stress_device


class Clock:
    def __init__(self):
        self.now = 100.0

    def sleep(self, seconds):
        self.now += seconds


class InlineExecutor:
    def __init__(self, **_):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def submit(self, operation):
        result = Future()
        # The test measures the coordinator's phases, without background phones.
        result.set_result(None if operation.__name__ == "phone" else operation())
        return result


def connection():
    result = MagicMock()
    response = result.getresponse.return_value
    response.status = 200
    response.isclosed.side_effect = [False, True]
    response.read1.return_value = json.dumps({
        "device": "LockLink", "online": True, "state": "locked", "armed": False,
        "health": {"boot": 1, "uptime_s": 10, "allocation_failures": 0},
    }).encode()
    return result


class StressToolTests(unittest.TestCase):
    def test_expired_run_budget_starts_no_network_request(self):
        device = stress_device.Device("http://192.168.0.112", None)
        device.deadline = 100.0
        with patch.object(stress_device.time, "monotonic", return_value=100.0), \
                patch.object(stress_device.http.client, "HTTPConnection", return_value=connection()) as transport:
            with self.assertRaises(TimeoutError):
                device.status()
            transport.assert_not_called()

    def test_connect_timeout_uses_remaining_run_budget(self):
        device = stress_device.Device("http://192.168.0.112", None)
        device.deadline = 100.25
        with patch.object(stress_device.time, "monotonic", return_value=100.0), \
                patch.object(stress_device.http.client, "HTTPConnection", return_value=connection()) as transport:
            device.status()
            self.assertLessEqual(transport.call_args.kwargs["timeout"], 0.25)

    def test_minutes_above_fifteen_are_rejected_before_loading_key(self):
        with patch.object(stress_device, "load_key", side_effect=AssertionError("Key must not be read")) as key, \
                patch("sys.argv", ["stress_device.py", "--minutes", "16", "--output", "unused.json"]), \
                redirect_stderr(io.StringIO()):
            try:
                stress_device.main()
            except (SystemExit, AssertionError) as error:
                self.assertIsInstance(error, SystemExit)
                self.assertEqual(error.code, 2)
            else:
                self.fail("An excessive run duration was accepted")
            key.assert_not_called()

    def test_tail_phases_share_total_budget_and_cannot_claim_pass(self):
        clock = Clock()
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "result.json"
            with patch.object(stress_device.time, "monotonic", side_effect=lambda: clock.now), \
                    patch.object(stress_device.time, "sleep", side_effect=clock.sleep), \
                    patch.object(stress_device, "ThreadPoolExecutor", InlineExecutor), \
                    patch.object(stress_device, "load_key", return_value=None), \
                    patch.object(stress_device.http.client, "HTTPConnection", side_effect=lambda *a, **k: connection()), \
                    patch("sys.argv", ["stress_device.py", "--minutes", "0.1", "--burst-rounds", "1", "--output", str(output)]), \
                    redirect_stdout(io.StringIO()):
                result = stress_device.main()
            summary = json.loads(output.read_text(encoding="utf-8"))
            self.assertLessEqual(summary["duration_s"], 6.0)
            self.assertTrue(summary["budget_exhausted"])
            self.assertEqual(result, 1)


if __name__ == "__main__":
    unittest.main()
