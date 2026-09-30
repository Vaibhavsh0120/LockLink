"""Verify C3 images and factory packaging without printing embedded credentials."""
import csv
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]


def verify(build: Path) -> None:
    images = {name: (build / name).read_bytes() for name in (
        "firmware.bin", "bootloader.bin", "partitions.bin", "firmware.factory.bin"
    )}
    if not all(images.values()):
        raise ValueError("Missing or empty firmware image")
    for name in ("firmware.bin", "bootloader.bin"):
        image = images[name]
        if len(image) < 24 or image[0] != 0xE9 or struct.unpack_from("<H", image, 12)[0] != 5:
            raise ValueError(f"{name} is not an ESP32-C3 image")
        if image[3] >> 4 != 2:
            raise ValueError(f"{name} is not configured for 4 MB flash")
        if image[2] != 2 or image[3] & 0xF != 0:
            raise ValueError(f"{name} must use DIO flash mode at 40 MHz for the Super Mini")
    entries = []
    for row in csv.reader(ROOT.joinpath("partitions.csv").read_text().splitlines()):
        if not row or row[0].lstrip().startswith("#"):
            continue
        name, kind, subtype, offset, size = [field.strip() for field in row[:5]]
        entries.append((name, kind, subtype, int(offset, 0), int(size, 0)))
    end = 0x9000
    for name, _, _, offset, size in entries:
        if offset < end or size <= 0 or offset + size > 0x400000:
            raise ValueError(f"Invalid or overlapping 4 MB partition: {name}")
        end = offset + size
    partitions = {entry[0]: entry for entry in entries}
    if partitions["otadata"][3:5] != (0xE000, 0x2000):
        raise ValueError("OTA data must match the factory packager's 0xe000 boot_app0 offset")
    app_offset, app_size = partitions["app0"][3:5]
    if len(images["firmware.bin"]) > app_size:
        raise ValueError("Firmware exceeds the app partition")
    # Compare compiled partition offsets/sizes to source, not just file presence.
    raw = images["partitions.bin"]
    for index, (name, _, _, offset, size) in enumerate(entries):
        magic, _, _, built_offset, built_size, label, _ = struct.unpack_from("<HBBII16sI", raw, index * 32)
        if magic != 0x50AA or label.split(b"\0")[0].decode() != name or (built_offset, built_size) != (offset, size):
            raise ValueError("Compiled partition image does not match partitions.csv")
    factory = images["firmware.factory.bin"]
    for name, offset in (("bootloader.bin", 0), ("partitions.bin", 0x8000), ("firmware.bin", app_offset)):
        image = images[name]
        if factory[offset:offset + len(image)] != image:
            raise ValueError(f"Factory image contains stale or misplaced {name}; rebuild the factory image")
    # Factory boot_app0 metadata must fit its partition and leave NVS erased.
    nvs_offset, nvs_size = partitions["nvs"][3:5]
    if factory[nvs_offset:nvs_offset + nvs_size] != b"\xff" * nvs_size:
        raise ValueError("Factory packaging writes into persistent NVS storage")
    print("C3 images verified: 4 MB layout, correct chip, current factory contents, erased NVS.")


if __name__ == "__main__":
    try:
        verify(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".pio/build/esp32-c3-supermini")
    except (OSError, ValueError, KeyError, struct.error) as error:
        print(f"Firmware verification failed: {error}", file=sys.stderr)
        sys.exit(1)
