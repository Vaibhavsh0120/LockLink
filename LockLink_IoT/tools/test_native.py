"""Compile and run actuator tests; hardware boundaries are simulated, not Wi-Fi."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="locklink-tests-") as temporary:
    for name, sources in {
        "challenge_pool": ["test/native/challenge_pool_test.cpp"],
        "terminal_history": ["test/native/terminal_history_test.cpp"],
        "json_writer": ["test/native/json_writer_test.cpp"],
        "lock_state": ["test/native/lock_state_test.cpp"],
        "local_network": ["test/native/local_network_test.cpp", "src/local_network.cpp"],
        "release_output": ["test/native/release_output_test.cpp", "src/release_output.cpp"],
        "led_output": ["test/native/release_output_test.cpp", "src/release_output.cpp"],
    }.items():
        binary = str(Path(temporary) / (name + (".exe" if os.name == "nt" else "")))
        subprocess.run([
            os.environ.get("CXX", "g++"), "-std=c++17", "-Wall", "-Wextra", "-Werror",
            "-Itest/native/fakes", "-Iinclude",
            "-DLOCKLINK_RELAY_ENABLED=" + ("0" if name == "led_output" else "1"),
            "-DLOCKLINK_IGNORE_PRIVATE_CONFIG=1",
            *sources, "-o", binary,
        ], cwd=ROOT, check=True)
        subprocess.run([binary], check=True)
