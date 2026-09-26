"""Compile and run actuator tests; hardware boundaries are simulated, not Wi-Fi."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="locklink-tests-") as temporary:
    for name, sources in {
        "lock_state": ["test/native/lock_state_test.cpp"],
        "release_output": ["test/native/release_output_test.cpp", "src/release_output.cpp"],
    }.items():
        binary = str(Path(temporary) / (name + (".exe" if os.name == "nt" else "")))
        subprocess.run([
            os.environ.get("CXX", "g++"), "-std=c++17", "-Wall", "-Wextra", "-Werror",
            "-Itest/native/fakes", "-Iinclude", "-DLOCKLINK_RELAY_ENABLED=1",
            *sources, "-o", binary,
        ], cwd=ROOT, check=True)
        subprocess.run([binary], check=True)
