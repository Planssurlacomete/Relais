"""Black-box publication guard checks using disposable, synthetic repositories.

Canaries are constructed at runtime so no complete credential, address or home
path is stored in the source snapshot. No production data or private denylist is
read. Run with: python3 -m unittest discover -s Tests -p 'test_privacy_guard.py'
"""

import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile


GUARD = Path(__file__).resolve().parents[1] / "Scripts/privacy-check.py"
APP_FILES = (
    "Contents/Info.plist",
    "Contents/PkgInfo",
    "Contents/MacOS/Relais",
    "Contents/Resources/AppIcon.icns",
    "Contents/Resources/ThirdPartyNotices.txt",
    "Contents/Resources/container-migration.plist",
    "Contents/_CodeSignature/CodeResources",
)
ARCHIVE_DOCUMENTS = (
    "INSTALLATION.txt", "RAPPORT.md", "THIRD-PARTY-NOTICES.txt",
    "Documentation/PublicDistribution/A-DEVELOPPEMENT.md",
    "Documentation/PublicDistribution/B-CONFIDENTIALITE.md",
    "Documentation/PublicDistribution/C-PUBLICATION.md",
)


class PrivacyGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="Relais-Privacy-Fixture-")
        self.addCleanup(self.temporary.cleanup)
        self.workspace = Path(self.temporary.name)
        self.repo = self.workspace / "source"
        self.repo.mkdir(mode=0o700)
        self.git("init", "--quiet")
        self.write("README.md", "Projet Alpha\n")
        self.git("add", "README.md")
        self.environment = os.environ.copy()
        self.environment.pop("RELAIS_PRIVACY_DENYLIST", None)

    def git(self, *arguments):
        return subprocess.run(["git", "-C", str(self.repo), *arguments], check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def write(self, name, content):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode("utf-8"))
        return path

    def run_guard(self, *arguments):
        return subprocess.run([sys.executable, str(GUARD), "--root", str(self.repo), *map(str, arguments)],
                              env=self.environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              encoding="utf-8", check=False)

    def assert_passes(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 finding(s)", result.stdout)

    def assert_rejects(self, result, category):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(category, result.stdout)
        self.assertIn("value redacted", result.stdout)

    def make_app(self):
        app = self.workspace / "Relais.app"
        for name in APP_FILES:
            path = app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"Synthetic production bundle fixture")
        return app

    def make_archive(self):
        archive = self.workspace / "distribution.zip"
        with zipfile.ZipFile(archive, "w") as output:
            for name in APP_FILES:
                output.writestr("Relais.app/" + name, b"Synthetic production bundle fixture")
            for name in ARCHIVE_DOCUMENTS:
                output.writestr(name, b"Synthetic public document")
        return archive

    def test_clean_tracked_and_untracked_sources_are_inspected(self):
        self.write("untracked.swift", "// Projet Bêta\n")
        self.assert_passes(self.run_guard())
        self.write("untracked.swift", "gh" + "p_" + "a" * 24)
        self.assert_rejects(self.run_guard(), "github-credential")
        self.git("add", "untracked.swift")
        self.assert_rejects(self.run_guard(), "github-credential")

    def test_tracked_ignored_file_is_still_checked(self):
        self.write(".gitignore", "ignored.log\n")
        self.write("ignored.log", "Synthetic local log")
        self.assert_passes(self.run_guard())
        self.git("add", "--force", "ignored.log")
        self.assert_rejects(self.run_guard(), "local-or-sensitive-file")

    def test_user_state_environment_backup_and_database_files_are_rejected(self):
        cases = (
            ("state.json", "user-state-file"),
            ("state.notes-recovery-fixture.json", "user-state-file"),
            (".env", "local-or-sensitive-file"),
            ("Backups/fixture.txt", "local-data-directory"),
            ("fixture.bak", "local-or-sensitive-file"),
            ("fixture.sqlite", "local-or-sensitive-file"),
        )
        for name, category in cases:
            with self.subTest(category=category):
                path = self.write(name, "Synthetic fixture")
                self.assert_rejects(self.run_guard(), category)
                path.unlink()

    def test_database_magic_is_detected_without_a_database_extension(self):
        self.write("fixture.bin", b"SQLite format 3\x00" + b"Synthetic payload")
        self.assert_rejects(self.run_guard(), "user-database")

    def test_paths_addresses_and_secret_categories_are_rejected(self):
        cases = (
            ("personal-home-path", "/".join(("", "Users", "synthetic", "fixture"))),
            ("email-address", "review" + "@" + "example.invalid"),
            ("github-credential", "gh" + "p_" + "a" * 24),
            ("service-credential", "s" + "k-" + "a" * 24),
            ("cloud-access-key", "A" + "KIA" + "A" * 16),
            ("private-key", "-----BEGIN " + "PRIVATE KEY-----"),
            ("credential-assignment", "password = " + '"' + "x" * 16 + '"'),
        )
        for category, canary in cases:
            with self.subTest(category=category):
                self.write("fixture.txt", canary)
                result = self.run_guard()
                self.assert_rejects(result, category)
                self.assertNotIn(canary, result.stdout + result.stderr)

    def test_findings_and_failures_do_not_disclose_values_or_file_names(self):
        marker = "SyntheticPrivateFilename"
        canary = "review" + "@" + "example.invalid"
        self.write(marker + ".txt", canary)
        result = self.run_guard()
        self.assert_rejects(result, "email-address")
        for value in (marker, canary, str(self.repo), str(self.workspace)):
            self.assertNotIn(value, result.stdout + result.stderr)
        missing = self.run_guard("--denylist", self.workspace / marker)
        self.assertEqual(missing.returncode, 2)
        for value in (marker, str(self.workspace)):
            self.assertNotIn(value, missing.stdout + missing.stderr)

    def test_unicode_denylist_has_word_boundaries_and_is_case_insensitive(self):
        term = "Projet Bêta"
        denylist = self.workspace / "private-terms"
        denylist.write_text(term + "\n", encoding="utf-8")
        self.write("fixture.txt", "Prefix" + term + "Suffix")
        self.assert_passes(self.run_guard("--denylist", denylist))
        self.write("fixture.txt", term.upper())
        result = self.run_guard("--denylist", denylist)
        self.assert_rejects(result, "local-denylist-term")
        self.assertNotIn(term, result.stdout + result.stderr)

    def test_unicode_denylist_is_detected_in_invalid_binary_surroundings(self):
        term = "Projet Bêta"
        denylist = self.workspace / "private-terms"
        denylist.write_text(term, encoding="utf-8")
        self.write("fixture.bin", b"\xff\x00" + term.encode("utf-8") + b"\xfe\x00")
        self.assert_rejects(self.run_guard("--denylist", denylist), "local-denylist-term")

    def test_retina_icon_names_are_not_reported_as_email_addresses(self):
        self.write("fixture.swift", '"icon_32x32' + "@" + '2x.png"')
        self.assert_passes(self.run_guard())

    def test_app_whitelist_accepts_only_reviewed_files(self):
        app = self.make_app()
        self.assert_passes(self.run_guard("--app", app))
        (app / "Contents/Resources/state.json").write_text("{}", encoding="utf-8")
        result = self.run_guard("--app", app)
        self.assert_rejects(result, "unexpected-bundle-file")
        self.assertIn("user-state-file", result.stdout)

    def test_app_missing_required_file_and_symlink_are_rejected(self):
        app = self.make_app()
        required = app / "Contents/PkgInfo"
        required.unlink()
        self.assert_rejects(self.run_guard("--app", app), "bundle-file-list-mismatch")
        target = self.workspace / "synthetic-target"
        target.write_text("Synthetic fixture", encoding="utf-8")
        required.symlink_to(target)
        self.assert_rejects(self.run_guard("--app", app), "symbolic-link")

    def test_zip_whitelist_accepts_clean_archive_and_rejects_user_state(self):
        archive = self.make_archive()
        self.assert_passes(self.run_guard("--archive", archive))
        with zipfile.ZipFile(archive, "a") as output:
            output.writestr("Relais.app/Contents/Resources/state.json", b"{}")
        result = self.run_guard("--archive", archive)
        self.assert_rejects(result, "unexpected-archive-entry")
        self.assertIn("user-state-file", result.stdout)

    def test_zip_comments_and_extra_metadata_are_rejected(self):
        archive = self.make_archive()
        with zipfile.ZipFile(archive, "a") as output:
            output.comment = b"Synthetic archive metadata"
            info = zipfile.ZipInfo("Relais.app/Contents/Resources/extra.txt")
            info.extra = b"\x55\x54\x00\x00"
            info.comment = b"Synthetic entry metadata"
            output.writestr(info, b"Synthetic fixture")
        self.assert_rejects(self.run_guard("--archive", archive), "archive-metadata")

    def test_zip_traversal_and_symlinks_are_rejected(self):
        archive = self.make_archive()
        with zipfile.ZipFile(archive, "a") as output:
            output.writestr("../fixture.txt", b"Synthetic fixture")
            link = zipfile.ZipInfo("Relais.app/Contents/Resources/link")
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            output.writestr(link, b"synthetic-target")
        result = self.run_guard("--archive", archive)
        self.assert_rejects(result, "unsafe-distribution-path")
        self.assertIn("symbolic-link", result.stdout)


if __name__ == "__main__":
    unittest.main()
