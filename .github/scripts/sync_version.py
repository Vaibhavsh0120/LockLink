"""Synchronize release metadata from the sole version field in pubspec.yaml."""
import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
SEMVER = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
DRAFT_MARKER = "<!-- release-notes: draft -->"
SYNC_COMMAND = "python .github/scripts/sync_version.py"


def valid_version(version: str) -> str:
    if not re.fullmatch(SEMVER + r"\+[1-9][0-9]*", version):
        raise ValueError("Version must be MAJOR.MINOR.PATCH+BUILD with a positive build number.")
    return version


def read_text(path: Path) -> str:
    # Preserve CRLF and UTF-8: native project/config files must not be reformatted.
    return path.read_bytes().decode("utf-8")


def read_version(pubspec: Path) -> str:
    values = re.findall(r"^version:[ \t]*(.*?)[ \t]*\r?$", read_text(pubspec), re.MULTILINE)
    if len(values) != 1:
        raise ValueError("pubspec.yaml must contain exactly one top-level version.")
    return valid_version(values[0].split("#", 1)[0].strip().strip("\"'"))


def replace(text: str, pattern: str, replacement, path: Path, count: int = 1) -> str:
    result, found = re.subn(pattern, replacement, text, flags=re.MULTILINE)
    if found != count:
        raise ValueError(f"Expected {count} version field(s) in {path}, found {found}; no files were changed.")
    return result


def version_updates(root: Path, version: str) -> dict[Path, str]:
    name, build = valid_version(version).split("+", 1)
    changes = {}

    def field(relative: str, prefix: str, suffix: str, value: str = name, count: int = 1):
        path = root / relative
        text = changes.get(path, read_text(path))
        pattern = "(" + prefix + ")" + SEMVER + "(" + suffix + ")"
        changes[path] = replace(text, pattern, lambda m: m[1] + value + m[2], path, count)

    field("LockLink_IoT/include/config.h", r'constexpr char version\[\] = "', r'";')
    field("LockLink_IoT/include/config.h", r'#error "LockLink v', r' requires')
    field("LockLink_App/lib/screens/settings_screen.dart", r"LockLink · v", "'")
    project = root / "LockLink_App/ios/Runner.xcodeproj/project.pbxproj"
    changes[project] = replace(read_text(project),
        r"(CURRENT_PROJECT_VERSION = )\d+(;\r?\n[ \t]*MARKETING_VERSION = )" + SEMVER + r"(;)",
        lambda m: m[1] + build + m[2] + name + m[3], project, 3)
    field("README.md", r"Current source version: \*\*v", r"\*\*")
    field("README.md", r"Version \*\*", r"\*\*")
    field("LockLink_App/README.md", r"The v", " Flutter client")
    for relative in ("ESP32_C3_SETUP.md", "WIDGETS.md", "OFFLINE_BEHAVIOR.md", "USB_DIAGNOSTICS.md"):
        field("LockLink_Docs/" + relative, r"^# [^\r\n]*\(v", r"\)")
    field("LockLink_Docs/ESP32_C3_SETUP.md", r"USB `STATUS` must report v", ",")
    for relative in ("README.md", "LockLink_Docs/WIDGETS.md", "LockLink_Docs/OFFLINE_BEHAVIOR.md", "LockLink_Docs/USB_DIAGNOSTICS.md"):
        path = root / relative
        changes[path] = replace(changes[path],
            r"\[v" + SEMVER + r" release notes\]\((LockLink_Docs/)?releases/v" + SEMVER + r"\.md\)",
            lambda m: f"[v{name} release notes]({m[1] or ''}releases/v{name}.md)", path)

    # Only the CURRENT notes can change. Old notes and dated diagnostic records
    # are historical evidence and must never be swept by a global replacement.
    notes = root / f"LockLink_Docs/releases/v{name}.md"
    if notes.exists():
        text = replace(read_text(notes), r"^# LockLink v" + SEMVER + r"(?=\r?$)",
                       f"# LockLink v{name}", notes)
        changes[notes] = replace(text, r"Source version \*\*" + SEMVER + r"\+\d+\*\*",
                                f"Source version **{version}**", notes)
    else:
        changes[notes] = (f"# LockLink v{name}\n\n{DRAFT_MARKER}\n\n"
            f"Source version **{version}**.\n\n## Changes\n\n"
            "Write the changes for this release.\n\n## Verification\n\n"
            "Record the checks run for this release and their limits.\n\n"
            "Remove the draft marker above when these notes are ready to publish.\n")
    return changes


def synchronize(root: Path = ROOT, version: str | None = None, check: bool = False) -> list[Path]:
    pubspec = root / "LockLink_App/pubspec.yaml"
    current = read_version(pubspec)
    selected = valid_version(version) if version is not None else current
    expected = version_updates(root, selected)  # Validate EVERY target before writing.
    if version is not None:
        expected[pubspec] = replace(read_text(pubspec),
            r"^(version:[ \t]*)([^#\r\n]+?)([ \t]*(?:#[^\r\n]*)?)(\r?)$",
            lambda m: m[1] + selected + m[3] + m[4], pubspec)
    changed = [p for p, text in expected.items() if not p.exists() or read_text(p) != text]
    if check and changed:
        names = ", ".join(str(p.relative_to(root)) for p in changed)
        raise ValueError(f"Version metadata is out of sync: {names}. Run `{SYNC_COMMAND}`.")
    if not check:
        for path in changed:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(expected[path].encode("utf-8"))
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--set", metavar="VERSION+BUILD", help="Set pubspec's version and synchronize all metadata.")
    group.add_argument("--check", action="store_true", help="Check synchronization without changing files.")
    args = parser.parse_args()
    try:
        changed = synchronize(version=args.set, check=args.check)
        version = read_version(ROOT / "LockLink_App/pubspec.yaml")
    except (OSError, UnicodeError, ValueError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    verb = "Checked" if args.check else "Synchronized"
    print(f"{verb} {version}; {len(changed)} file(s) changed.")
    if not args.check and any(p.parent.name == "releases" and DRAFT_MARKER in read_text(p) for p in changed):
        print("New release notes are a draft. Complete them before publishing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
