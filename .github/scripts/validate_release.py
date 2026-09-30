"""Bind a manual release to the checked-out app version and remote tag commit."""

import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
SEMVER = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"


def read_version(pubspec: Path) -> str:
    versions = re.findall(r"^version:\s*(.*?)\s*$", pubspec.read_text(encoding="utf-8"), re.MULTILINE)
    if len(versions) != 1:
        raise ValueError("pubspec.yaml must contain exactly one top-level version.")
    version = versions[0].split("#", 1)[0].strip().strip("\"'")
    if not re.fullmatch(SEMVER + r"\+[1-9][0-9]*", version):
        raise ValueError("App version must include a semantic version and positive build number, e.g. 1.9.2+192.")
    return version


def validate_version(tag: str, pubspec: Path) -> str:
    if not re.fullmatch("v" + SEMVER, tag):
        raise ValueError("Release tag must use vMAJOR.MINOR.PATCH, optionally with a prerelease suffix.")
    version = read_version(pubspec)
    expected_tag = "v" + version.split("+", 1)[0]
    if tag != expected_tag:
        raise ValueError(f"Release tag must be {expected_tag} to match pubspec.yaml version {version}.")
    return version


def git_output(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=root, check=True, capture_output=True, text=True,
    ).stdout.strip()


def validate_metadata(version: str, root: Path) -> None:
    name, build = version.split("+", 1)
    settings = (root / "LockLink_App/lib/screens/settings_screen.dart").read_text(encoding="utf-8")
    firmware = (root / "LockLink_IoT/include/config.h").read_text(encoding="utf-8")
    project = (root / "LockLink_App/ios/Runner.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    if re.findall(r"LockLink · v([^']+)'", settings) != [name]:
        raise ValueError("Settings footer must match the pubspec release version.")
    if re.findall(r'constexpr char version\[\] = "([^"]+)";', firmware) != [name]:
        raise ValueError("Firmware version must match the pubspec release version.")
    widgets = re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);\s*MARKETING_VERSION = ([^;]+);", project)
    if widgets != [(build, name)] * 3:
        raise ValueError("All three iOS widget configurations must match the app version and build number.")


def validate_remote_tag(tag: str, root: Path, expected_sha: str) -> None:
    head = git_output(root, "rev-parse", "HEAD")
    if head != expected_sha:
        raise ValueError("Checkout commit differs from the workflow commit; refusing to publish different source.")
    ref = "refs/tags/" + tag
    output = git_output(root, "ls-remote", "--tags", "origin", ref, ref + "^{}")
    refs = {ref_name: sha for sha, ref_name in (line.split() for line in output.splitlines())}
    # Annotated tags have a peeled commit entry; lightweight tags use the ref itself.
    tagged_sha = refs.get(ref + "^{}", refs.get(ref))
    if tagged_sha is not None and tagged_sha != head:
        raise ValueError("Existing release tag points to a different commit; build from that tag or choose a new version.")


def main() -> int:
    try:
        args = sys.argv[1:]
        if args not in ([], ["--metadata-only"]):
            raise ValueError("Usage: validate_release.py [--metadata-only]")
        tag = os.environ.get("RELEASE_TAG", "")
        if args == ["--metadata-only"]:
            version = read_version(ROOT / "LockLink_App/pubspec.yaml")
            tag = "v" + version.split("+", 1)[0]
        version = validate_version(tag, ROOT / "LockLink_App/pubspec.yaml")
        validate_metadata(version, ROOT)
        if args == ["--metadata-only"]:
            print(f"Project version metadata passed: {version}.")
            return 0
        expected_sha = os.environ.get("GITHUB_SHA") or git_output(ROOT, "rev-parse", "HEAD")
        validate_remote_tag(tag, ROOT, expected_sha)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        message = "Could not read Git checkout or remote tags." if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f"::error::{message}", file=sys.stderr)
        return 1
    print(f"Release preflight passed: {tag}, app version {version}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
