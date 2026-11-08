#!/bin/bash
# A deterministic ZIP of the signed app and installation notes. No AppleDouble,
# extended attributes, resource forks, ZIP comments or extra fields are included.
# This packages the existing signature; it does not sign or notarize anything.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$PROJECT_DIR/../Relais.app}"
if [[ ! -f "$APP_PATH/Contents/MacOS/Relais" ]]; then
    echo 'Build the app using Scripts/build.sh first.' >&2
    exit 1
fi
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
if [[ "$BUNDLE_IDENTIFIER" != org.relaisapp.Relais ]]; then
    echo 'Only the production Relais bundle may be packaged for distribution.' >&2
    exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ZIP_PATH="${2:-$PROJECT_DIR/../Relais-v${VERSION}-macOS-AppleSilicon.zip}"
codesign --verify --strict "$APP_PATH"
python3 "$PROJECT_DIR/Scripts/privacy-check.py" --root "$PROJECT_DIR" --app "$APP_PATH"
python3 - "$PROJECT_DIR" "$APP_PATH" "$ZIP_PATH" <<'PY'
from pathlib import Path
import datetime
import os
import stat
import sys
import tempfile
import zipfile
import importlib.util

project, app, output = map(lambda value: Path(value).resolve(), sys.argv[1:])
spec = importlib.util.spec_from_file_location("relais_privacy_guard", project / "Scripts/privacy-check.py")
guard_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard_module)
actual_files = {path.relative_to(app).as_posix() for path in app.rglob("*") if path.is_file() or path.is_symlink()}
actual_directories = {path.relative_to(app).as_posix() for path in app.rglob("*") if path.is_dir()}
if actual_files != guard_module.APP_FILES or not actual_directories.issubset(guard_module.APP_DIRECTORIES):
    raise ValueError("The production bundle does not match the reviewed file whitelist")
output.parent.mkdir(parents=True, exist_ok=True)
# Fixed timestamp by default; SOURCE_DATE_EPOCH can select a reproducible date.
epoch = max(315532800, min(int(os.environ.get("SOURCE_DATE_EPOCH", "315532800")), 4354819198))
timestamp = datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).timetuple()[:6]
entries = [(Path("Relais.app"), app)]
entries += [(Path("Relais.app") / p.relative_to(app), p) for p in app.rglob("*")]
entries += [(Path(name), project / name) for name in sorted(guard_module.ARCHIVE_DOCUMENTS)]
handle, temporary = tempfile.mkstemp(prefix=".relais-package-", suffix=".zip", dir=output.parent)
os.close(handle)
try:
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, source in sorted(entries, key=lambda item: item[0].as_posix()):
            if source.is_symlink():
                raise ValueError("Symbolic links are not expected in this standalone app")
            if name.name.startswith("._") or name.name == ".DS_Store" or "__MACOSX" in name.parts:
                continue
            directory = source.is_dir()
            info = zipfile.ZipInfo(name.as_posix() + ("/" if directory else ""), date_time=timestamp)
            info.create_system = 3
            permissions = 0o755 if directory or source.stat().st_mode & stat.S_IXUSR else 0o644
            info.external_attr = ((stat.S_IFDIR if directory else stat.S_IFREG) | permissions) << 16
            if directory:
                info.external_attr |= 0x10
            info.extra = b""
            info.comment = b""
            info.compress_type = zipfile.ZIP_STORED if directory else zipfile.ZIP_DEFLATED
            archive.writestr(info, b"" if directory else source.read_bytes(), compresslevel=9)
    with zipfile.ZipFile(temporary) as archive:
        assert not archive.comment and all(not i.extra and not i.comment for i in archive.infolist())
        assert archive.testzip() is None
    os.replace(temporary, output)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
print("PASS distribution archive assembled without extra metadata")
PY
python3 "$PROJECT_DIR/Scripts/privacy-check.py" --root "$PROJECT_DIR" --archive "$ZIP_PATH"
