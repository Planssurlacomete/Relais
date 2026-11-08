#!/bin/bash
# Run in a macOS GUI login session. Only synthetic data and a unique app identity
# are used. No production Relais state or pre-existing container is modified.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${RELAIS_BUILD_DIR:-$PROJECT_DIR/.build-cli}"
mkdir -p "$BUILD_DIR/ModuleCache"
SESSION_DIR="$(mktemp -d "$BUILD_DIR/security-test.XXXXXXXX")"
TEST_UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
BUNDLE_ID="org.relaisapp.Relais.SecurityTest.t$TEST_UUID"
FIXTURE_NAME="RelaisMigrationTest-$TEST_UUID"
FIXTURE_DIR="$HOME/Library/Application Support/$FIXTURE_NAME"
APP_PATH="$SESSION_DIR/RelaisSecurityProbe.app"
LOG_PATH="$SESSION_DIR/probe.log"
if [[ -e "$HOME/Library/Containers/$BUNDLE_ID" ]]; then
    echo 'FAIL first-launch test identity already has a container' >&2
    exit 1
fi

cleanup_fixture() {
    # Remove only files this invocation created. Never delete an app container.
    if [[ "$FIXTURE_DIR" == "$HOME/Library/Application Support/RelaisMigrationTest-$TEST_UUID" && -f "$FIXTURE_DIR/.relais-security-fixture" ]]; then
        rm -f "$FIXTURE_DIR/state.json" "$FIXTURE_DIR/read-canary.txt" "$FIXTURE_DIR/write-canary.txt" "$FIXTURE_DIR/.relais-security-fixture"
        rmdir "$FIXTURE_DIR" 2>/dev/null || true
    fi
}
trap cleanup_fixture EXIT

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
# Exclusive creation proves the source is a new synthetic fixture directory.
python3 - "$FIXTURE_DIR" "$FIXTURE_NAME" "$APP_PATH" "$BUNDLE_ID" <<'PY'
import json
import os
import plistlib
import sys
from pathlib import Path
fixture = Path(sys.argv[1])
fixture_name = sys.argv[2]
app = Path(sys.argv[3])
bundle_id = sys.argv[4]
fixture.mkdir(mode=0o700, parents=False, exist_ok=False)
(fixture / ".relais-security-fixture").touch(exist_ok=False)
(fixture / "read-canary.txt").write_text("Synthetic sandbox canary only.\n", encoding="utf-8")
state = {
    "schemaVersion": 1,
    "projects": [{
        "id": "D5CA5407-9B7F-4C58-83A9-2A0136514219",
        "name": "Projet Alpha",
        "position": "right",
        "customLabels": {"left": "Création", "right": "Validation"}
    }],
    "globalLabels": {"left": "Équipe A", "right": "Équipe B"},
    "windowFrame": {"x": 111, "y": 222, "width": 248, "height": 230},
    "panelVisible": False
}
(fixture / "state.json").write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
os.chmod(fixture / "state.json", 0o600)
info = {
    "CFBundleIdentifier": bundle_id,
    "CFBundleExecutable": "RelaisSecurityProbe",
    "CFBundleName": "Relais Security Probe",
    "CFBundlePackageType": "APPL",
    "CFBundleVersion": "1",
    "LSMinimumSystemVersion": "14.0",
    "LSUIElement": True,
    "NSPrincipalClass": "NSApplication"
}
with (app / "Contents/Info.plist").open("wb") as stream:
    plistlib.dump(info, stream)
manifest = {"Move": [[
    "${ApplicationSupport}/" + fixture_name + "/state.json",
    "${ApplicationSupport}/Relais/state.json"
]]}
with (app / "Contents/Resources/container-migration.plist").open("wb") as stream:
    plistlib.dump(manifest, stream)
PY

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -parse-as-library -O -whole-module-optimization -swift-version 5 \
    -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_DIR/ModuleCache" -framework AppKit \
    "$PROJECT_DIR/Relais/Models/RelayModels.swift" \
    "$PROJECT_DIR/Relais/Persistence/ProjectStore.swift" \
    "$PROJECT_DIR/Tests/Sandbox/SandboxProbe.swift" \
    -o "$APP_PATH/Contents/MacOS/RelaisSecurityProbe"
codesign --force --sign - --identifier "$BUNDLE_ID" --options runtime --timestamp=none \
    --entitlements "$PROJECT_DIR/Relais/Relais.entitlements" "$APP_PATH" 2> "$SESSION_DIR/signing.log"
codesign --verify --strict "$APP_PATH"
codesign --display --verbose=4 "$APP_PATH" 2> "$SESSION_DIR/signature-details.txt"
if ! rg -q '^CodeDirectory .*flags=.*runtime' "$SESSION_DIR/signature-details.txt"; then
    echo 'FAIL probe signature does not enable Hardened Runtime' >&2
    exit 1
fi
echo 'PASS probe signature verifies with Hardened Runtime enabled'
codesign --display --entitlements - --xml "$APP_PATH" > "$SESSION_DIR/entitlements.plist" 2> "$SESSION_DIR/inspection.log"
python3 - "$SESSION_DIR/entitlements.plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "rb") as stream:
    actual = plistlib.load(stream)
if actual != {"com.apple.security.app-sandbox": True}:
    raise SystemExit("FAIL probe uses exactly the production sandbox-only entitlements")
print("PASS probe uses exactly the production sandbox-only entitlements")
PY
# Launch the signed bundle executable directly so a short-lived probe does not
# race LaunchServices' application-ready handshake. Sandbox setup precedes main.
PROBE_STATUS=0
"$APP_PATH/Contents/MacOS/RelaisSecurityProbe" \
    "$FIXTURE_DIR/read-canary.txt" "$FIXTURE_DIR/write-canary.txt" > "$LOG_PATH" 2>&1 || PROBE_STATUS=$?
# stdout contains only generic PASS/FAIL descriptions, never user names or paths.
if ! rg '^((PASS|FAIL) |RESULT )' "$LOG_PATH"; then
    echo 'FAIL probe produced no assertion output' >&2
    exit 1
fi
if ! rg -q '^RESULT 0 failure\(s\)$' "$LOG_PATH"; then
    echo 'FAIL isolated sandbox security probe' >&2
    exit 1
fi
if [[ "$PROBE_STATUS" != 0 ]]; then
    echo 'FAIL sandbox probe process exit status' >&2
    exit 1
fi
if [[ -e "$FIXTURE_DIR/write-canary.txt" ]]; then
    echo 'FAIL external write canary was created' >&2
    exit 1
fi
printf 'PASS isolated sandbox security probe completed\n'
printf 'INFO isolated test container retained; no existing container was deleted\n'
