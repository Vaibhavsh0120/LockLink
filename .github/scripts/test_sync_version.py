"""Version changes in isolated copies; never change the real release version."""
from pathlib import Path
from io import BytesIO
import os
import shutil
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

import sync_version
import validate_release


class VersionSyncTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="locklink-version-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.current = sync_version.read_version(sync_version.ROOT / "LockLink_App/pubspec.yaml")
        paths = [
            "LockLink_App/pubspec.yaml", "LockLink_App/lib/screens/settings_screen.dart",
            "LockLink_App/ios/Runner.xcodeproj/project.pbxproj", "LockLink_IoT/include/config.h",
            "README.md", "LockLink_App/README.md", "LockLink_Docs/ESP32_C3_SETUP.md",
            "LockLink_Docs/MATTER_SETUP.md", "LockLink_Docs/APPLE_HOME_QUICKSTART.md",
            "LockLink_Docs/WIDGETS.md", "LockLink_Docs/TERMINAL_PLAN.md",
            "LockLink_Docs/OFFLINE_BEHAVIOR.md", "LockLink_Docs/CONNECTION_DIAGNOSIS_2026-10-01.md",
            f"LockLink_Docs/releases/v{self.current.split('+')[0]}.md",
        ]
        for relative in paths:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(sync_version.ROOT / relative, target)
        self.target = "99.88.77+998877"

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}

    def test_one_version_updates_every_platform_and_preserves_history(self):
        historical = self.root / f"LockLink_Docs/releases/v{self.current.split('+')[0]}.md"
        old_notes = historical.read_bytes()
        diagnosis = self.root / "LockLink_Docs/CONNECTION_DIAGNOSIS_2026-10-01.md"
        old_diagnosis = diagnosis.read_bytes()
        sync_version.synchronize(self.root, version=self.target)
        self.assertEqual(sync_version.read_version(self.root / "LockLink_App/pubspec.yaml"), self.target)
        self.assertIn('version[] = "99.88.77";', (self.root / "LockLink_IoT/include/config.h").read_text(encoding="utf-8"))
        self.assertIn("LockLink · v99.88.77", (self.root / "LockLink_App/lib/screens/settings_screen.dart").read_text(encoding="utf-8"))
        project = (self.root / "LockLink_App/ios/Runner.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        self.assertEqual(project.count("CURRENT_PROJECT_VERSION = 998877;"), 3)
        self.assertEqual(project.count("MARKETING_VERSION = 99.88.77;"), 3)
        self.assertIn("Current source version: **v99.88.77**.", (self.root / "README.md").read_text(encoding="utf-8"))
        self.assertIn("releases/v99.88.77.md", (self.root / "LockLink_Docs/WIDGETS.md").read_text(encoding="utf-8"))
        self.assertEqual(historical.read_bytes(), old_notes)
        self.assertEqual(diagnosis.read_bytes(), old_diagnosis)
        validate_release.validate_metadata(self.target, self.root)
        self.assertEqual(sync_version.synchronize(self.root), [])

    def test_check_detects_drift_without_writing(self):
        pubspec = self.root / "LockLink_App/pubspec.yaml"
        pubspec.write_bytes(pubspec.read_bytes().replace(self.current.encode(), self.target.encode()))
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "sync_version.py"):
            sync_version.synchronize(self.root, check=True)
        self.assertEqual(self.snapshot(), before)

    def test_invalid_version_and_changed_target_fail_before_any_write(self):
        before = self.snapshot()
        with self.assertRaises(ValueError):
            sync_version.synchronize(self.root, version="../../release+1")
        self.assertEqual(self.snapshot(), before)
        project = self.root / "LockLink_App/ios/Runner.xcodeproj/project.pbxproj"
        widget_version = ("MARKETING_VERSION = " + self.current.split("+")[0] + ";").encode()
        project.write_bytes(project.read_bytes().replace(widget_version, b"OTHER_VERSION = 0;", 1))
        before = self.snapshot()
        with self.assertRaises(ValueError):
            sync_version.synchronize(self.root, version=self.target)
        self.assertEqual(self.snapshot(), before)

    def test_new_notes_are_drafts_and_cannot_be_published(self):
        sync_version.synchronize(self.root, version=self.target)
        notes = self.root / "LockLink_Docs/releases/v99.88.77.md"
        self.assertIn(sync_version.DRAFT_MARKER, notes.read_text(encoding="utf-8"))
        with self.assertRaisesRegex(ValueError, "draft"):
            validate_release.require_finished_notes(self.target, self.root)
        notes.write_text(notes.read_text(encoding="utf-8").replace(sync_version.DRAFT_MARKER, ""), encoding="utf-8")
        validate_release.require_finished_notes(self.target, self.root)

    def test_crlf_and_pubspec_comment_survive_sync(self):
        pubspec = self.root / "LockLink_App/pubspec.yaml"
        pubspec.write_bytes(pubspec.read_bytes().replace(self.current.encode(), f"'{self.current}'  # release".encode()))
        for path in self.root.rglob("*"):
            if path.is_file():
                path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
        sync_version.synchronize(self.root, version=self.target)
        self.assertIn(b"version: 99.88.77+998877  # release\r\n", pubspec.read_bytes())
        for relative in ("LockLink_IoT/include/config.h", "LockLink_App/ios/Runner.xcodeproj/project.pbxproj"):
            self.assertNotRegex((self.root / relative).read_bytes(), rb"(?<!\r)\n")

    def test_tag_must_match_canonical_version(self):
        sync_version.synchronize(self.root, version=self.target)
        pubspec = self.root / "LockLink_App/pubspec.yaml"
        self.assertEqual(validate_release.validate_version("v99.88.77", pubspec), self.target)
        with self.assertRaises(ValueError):
            validate_release.validate_version("v2.0.1", pubspec)

    def test_manual_preflight_derives_tag_and_emits_job_outputs(self):
        sync_version.synchronize(self.root)
        notes = self.root / f"LockLink_Docs/releases/v{self.current.split('+')[0]}.md"
        notes.write_text(notes.read_text(encoding="utf-8").replace(sync_version.DRAFT_MARKER, ""), encoding="utf-8")
        output = self.root / "job-output.txt"
        with patch.object(validate_release, "ROOT", self.root), \
             patch("sys.argv", ["validate_release.py"]), \
             patch.dict(os.environ, {"GITHUB_REPOSITORY": "owner/repo", "GITHUB_SHA": "abc", "GITHUB_OUTPUT": str(output)}, clear=True), \
             patch.object(validate_release, "require_unpublished") as check, \
             patch.object(validate_release, "git_output", side_effect=["abc", ""]):
            self.assertEqual(validate_release.main(), 0)
        self.assertEqual(check.call_args.args[0], "v" + self.current.split("+")[0])
        self.assertIn("tag=v" + self.current.split("+")[0], output.read_text())
        self.assertIn("version=" + self.current, output.read_text())


class PublishedVersionTests(unittest.TestCase):
    def test_published_version_stops_with_change_version_instruction(self):
        with patch.object(validate_release, "urlopen", return_value=BytesIO(b'{"draft":false}')):
            with self.assertRaisesRegex(ValueError, "already published.*pubspec.yaml"):
                validate_release.require_unpublished("v2.1.0", "owner/repo")

    def test_missing_release_is_allowed_but_permission_failure_is_not(self):
        for status in (404, 403):
            with patch.object(validate_release, "urlopen", side_effect=HTTPError("https://api.github.com", status, "error", {}, None)):
                if status == 404:
                    validate_release.require_unpublished("v2.1.0", "owner/repo")
                else:
                    with self.assertRaisesRegex(ValueError, "Cannot check.*403"):
                        validate_release.require_unpublished("v2.1.0", "owner/repo")


if __name__ == "__main__":
    unittest.main()
