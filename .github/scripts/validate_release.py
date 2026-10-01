"""Derive a new manual release from pubspec; reject published versions and drift."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from sync_version import DRAFT_MARKER, SEMVER, read_text, read_version, synchronize


ROOT = Path(__file__).resolve().parents[2]


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
    if read_version(root / "LockLink_App/pubspec.yaml") != version:
        raise ValueError("Release version must match pubspec.yaml.")
    synchronize(root, check=True)


def require_finished_notes(version: str, root: Path) -> None:
    notes = root / "LockLink_Docs/releases" / f"v{version.split('+')[0]}.md"
    if DRAFT_MARKER in read_text(notes):
        raise ValueError(f"Release notes are a draft: {notes.name}. Complete them and remove the draft marker before publishing.")


def require_unpublished(tag: str, repository: str, token: str = "", api_url: str = "https://api.github.com") -> None:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("GITHUB_REPOSITORY must identify the repository before checking published versions.")
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "LockLink-release-check"}
    if token:
        headers["Authorization"] = "Bearer " + token
    request = Request(f"{api_url.rstrip('/')}/repos/{repository}/releases/tags/{tag}", headers=headers)
    try:
        with urlopen(request, timeout=20) as response:
            release = json.load(response)
    except HTTPError as error:
        if error.code == 404:
            return
        raise ValueError(f"Cannot check published versions: GitHub returned HTTP {error.code}.") from None
    except (URLError, OSError, ValueError):
        raise ValueError("Cannot check published versions: GitHub did not return a valid release response.") from None
    if not isinstance(release, dict) or not isinstance(release.get("draft"), bool):
        raise ValueError("Cannot check published versions: invalid GitHub release response.")
    state = "already exists as a draft" if release["draft"] else "is already published"
    raise ValueError(f"{tag} {state}. Change version in LockLink_App/pubspec.yaml, run python .github/scripts/sync_version.py, commit and rerun Manual Release.")


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
        version = read_version(ROOT / "LockLink_App/pubspec.yaml")
        tag = os.environ.get("RELEASE_TAG") or "v" + version.split("+", 1)[0]
        version = validate_version(tag, ROOT / "LockLink_App/pubspec.yaml")
        if args == ["--metadata-only"]:
            validate_metadata(version, ROOT)
            print(f"Project version metadata passed: {version}.")
            return 0
        # Check for an existing release before spending time on platform builds.
        require_unpublished(tag, os.environ.get("GITHUB_REPOSITORY") or os.environ.get("GH_REPO", ""),
                            os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN", ""),
                            os.environ.get("GITHUB_API_URL", "https://api.github.com"))
        validate_metadata(version, ROOT)
        require_finished_notes(version, ROOT)
        expected_sha = os.environ.get("GITHUB_SHA") or git_output(ROOT, "rev-parse", "HEAD")
        validate_remote_tag(tag, ROOT, expected_sha)
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
                output.write(f"tag={tag}\nversion={version}\n")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        message = "Could not read Git checkout or remote tags." if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f"::error::{message}", file=sys.stderr)
        return 1
    print(f"Release preflight passed: {tag}, app version {version}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
