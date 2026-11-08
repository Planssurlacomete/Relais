#!/usr/bin/env python3
"""Offline publication guard; findings never include matched values or file names.

Scan tracked and non-ignored source files by default. --app and --archive add
distribution checks. A local --denylist (or RELAIS_PRIVACY_DENYLIST) can supply
one literal term per line without committing private identifiers to this script.
This is a conservative guard, supplemented by a dedicated secrets scanner and
review of historical Git/GitHub surfaces. It does not inspect the Git history.
"""

import argparse
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import zipfile


APP_FILES = frozenset({
    "Contents/Info.plist",
    "Contents/PkgInfo",
    "Contents/MacOS/Relais",
    "Contents/Resources/AppIcon.icns",
    "Contents/Resources/ThirdPartyNotices.txt",
    "Contents/Resources/container-migration.plist",
    "Contents/_CodeSignature/CodeResources",
})
APP_DIRECTORIES = frozenset({
    "Contents", "Contents/MacOS", "Contents/Resources", "Contents/_CodeSignature",
})
ARCHIVE_DOCUMENTS = frozenset({
    "INSTALLATION.txt", "RAPPORT.md", "THIRD-PARTY-NOTICES.txt",
    "Documentation/PublicDistribution/A-DEVELOPPEMENT.md",
    "Documentation/PublicDistribution/B-CONFIDENTIALITE.md",
    "Documentation/PublicDistribution/C-PUBLICATION.md",
})
FORBIDDEN_DIRECTORIES = frozenset({
    ".git", ".ssh", ".aws", ".local", "private-backups", "backups", "logs",
    "userdata", "user-data", "__MACOSX", "xcuserdata", "DerivedData",
})
FORBIDDEN_SUFFIXES = frozenset({
    ".log", ".crash", ".trace", ".har", ".heapsnapshot", ".bak", ".backup",
    ".sqlite", ".sqlite3", ".db", ".pem", ".key", ".p12", ".pfx", ".sarif",
})
PATTERNS = (
    ("personal-home-path", re.compile(r"/(?:Users|home)/[^/\s\"'<>\x00]+")),
    ("personal-home-path", re.compile(r"[A-Za-z]:[\\/](?:Users|Documents and Settings)[\\/][^\\/\s\"'<>\x00]+")),
    ("email-address", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
    ("private-key", re.compile(r"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----")),
    ("github-credential", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\b")),
    ("service-credential", re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b")),
    ("cloud-access-key", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("credential-assignment", re.compile(r"(?i)\b(?:api[_-]?key|secret|password|access[_-]?token)\b\s*[:=]\s*[\"'][^\"'\s]{12,}[\"']")),
)


class Guard:
    def __init__(self, terms=()):
        self.findings = set()
        self.objects = 0
        self.patterns = list(PATTERNS)
        self.patterns.extend(("local-denylist-term", re.compile(r"(?<!\w)" + re.escape(term) + r"(?!\w)", re.IGNORECASE))
                             for term in terms)

    def report(self, category, object_id, line=0):
        # File ordinals, not names or values: even a filename can contain PII.
        self.findings.add((category, object_id, line))

    def identifier(self):
        self.objects += 1
        return self.objects

    def name(self, relative, object_id):
        path = PurePosixPath(relative)
        name = path.name.lower()
        if path.is_absolute() or ".." in path.parts:
            self.report("unsafe-distribution-path", object_id)
        if any(part.casefold() in {item.casefold() for item in FORBIDDEN_DIRECTORIES} for part in path.parts):
            self.report("local-data-directory", object_id)
        if (name.startswith("state") and name.endswith(".json")) or name.startswith(".state-"):
            self.report("user-state-file", object_id)
        if (name in {".ds_store", ".env", ".privacy-denylist"}
                or name.startswith(("._", ".env.", ".privacy-denylist.", "gitleaks-report", "privacy-report"))
                or path.suffix.lower() in FORBIDDEN_SUFFIXES
                or name.endswith((".db-wal", ".db-shm", ".sqlite-wal", ".sqlite-shm"))):
            self.report("local-or-sensitive-file", object_id)

    def data(self, content, object_id):
        if content.startswith(b"SQLite format 3\x00"):
            self.report("user-database", object_id)
        # Preserve valid Unicode strings embedded in icons and Mach-O binaries,
        # even when surrounding bytes are not UTF-8. ASCII-only extraction would
        # miss accented local denylist terms. Replacement never prints the data.
        text = content.decode("utf-8", errors="replace")
        for line, value in enumerate(text.splitlines(), start=1):
            for category, pattern in self.patterns:
                matches = list(pattern.finditer(value))
                # Retina icon filenames contain an at-sign but are not addresses.
                if category == "email-address":
                    matches = [match for match in matches
                               if not re.fullmatch(r"icon_\d+x\d+@[23]x\.png", match.group())]
                if matches:
                    self.report(category, object_id, line)

    def file(self, path, relative):
        object_id = self.identifier()
        self.name(relative, object_id)
        if path.is_symlink():
            self.report("symbolic-link", object_id)
        elif path.is_file():
            self.data(path.read_bytes(), object_id)
        else:
            self.report("unexpected-file-type", object_id)

    def sources(self, root):
        result = subprocess.run(["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                                check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        for raw in sorted(set(result.stdout.split(b"\x00")) - {b""}):
            relative = os.fsdecode(raw)
            path = root / relative
            # A tracked file deleted in the working tree is absent from the snapshot.
            if path.exists() or path.is_symlink():
                self.file(path, relative)

    def app(self, app):
        found = set()
        for path in sorted(app.rglob("*")):
            relative = path.relative_to(app).as_posix()
            if path.is_dir() and not path.is_symlink():
                if relative not in APP_DIRECTORIES:
                    self.report("unexpected-bundle-directory", self.identifier())
                continue
            found.add(relative)
            self.file(path, relative)
            if relative not in APP_FILES:
                self.report("unexpected-bundle-file", self.objects)
        if found != APP_FILES:
            self.report("bundle-file-list-mismatch", self.identifier())

    def archive(self, path):
        found = set()
        with zipfile.ZipFile(path) as archive:
            if archive.comment:
                self.report("archive-metadata", self.identifier())
            if archive.testzip() is not None:
                self.report("archive-integrity", self.identifier())
            for info in archive.infolist():
                object_id = self.identifier()
                name = info.filename.rstrip("/")
                self.name(name, object_id)
                if name in found:
                    self.report("duplicate-archive-entry", object_id)
                found.add(name)
                if info.extra or info.comment:
                    self.report("archive-metadata", object_id)
                if stat.S_ISLNK(info.external_attr >> 16):
                    self.report("symbolic-link", object_id)
                if name == "Relais.app" and info.is_dir():
                    continue
                if name.startswith("Relais.app/"):
                    relative = name.removeprefix("Relais.app/")
                    allowed = APP_DIRECTORIES if info.is_dir() else APP_FILES
                    if relative not in allowed:
                        self.report("unexpected-archive-entry", object_id)
                elif name not in ARCHIVE_DOCUMENTS or info.is_dir():
                    self.report("unexpected-archive-entry", object_id)
                if not info.is_dir():
                    self.data(archive.read(info), object_id)
        expected = {"Relais.app/" + name for name in APP_FILES} | set(ARCHIVE_DOCUMENTS)
        if not expected.issubset(found):
            self.report("archive-file-list-mismatch", self.identifier())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--app", type=Path, help="Also inspect a production bundle against its file whitelist")
    parser.add_argument("--archive", type=Path, help="Also inspect a distribution ZIP and its contents")
    parser.add_argument("--denylist", type=Path, default=os.environ.get("RELAIS_PRIVACY_DENYLIST"),
                        help="Private local file, one forbidden literal per line; never printed")
    args = parser.parse_args()
    try:
        terms = []
        if args.denylist:
            terms = [line.strip() for line in Path(args.denylist).read_text(encoding="utf-8").splitlines()
                     if line.strip() and not line.lstrip().startswith("#")]
        guard = Guard(terms)
        guard.sources(args.root.resolve())
        if args.app:
            guard.app(args.app.resolve())
        if args.archive:
            guard.archive(args.archive.resolve())
        for category, object_id, line in sorted(guard.findings):
            suffix = f" line {line}" if line else ""
            print(f"FAIL {category}: object#{object_id}{suffix}; value redacted")
        print(f"{'FAIL' if guard.findings else 'PASS'} privacy guard: {guard.objects} objects inspected; {len(guard.findings)} finding(s).")
        return 1 if guard.findings else 0
    except (OSError, ValueError, subprocess.SubprocessError, zipfile.BadZipFile):
        # Exception text can itself contain an absolute local path or filename.
        print("FAIL privacy guard could not inspect every requested input; details redacted.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
