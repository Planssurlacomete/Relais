#!/bin/bash
# Build a native Apple Silicon .app using the installed Apple command-line tools.
# No Xcode installation or third-party dependencies are required for this path.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$PROJECT_DIR/../Relais.app}"
BUILD_DIR="${RELAIS_BUILD_DIR:-$PROJECT_DIR/.build-cli}"
if [[ "$APP_PATH" != *.app ]]; then
    echo 'Usage: Scripts/build.sh [/absolute/path/Relais.app]' >&2
    exit 2
fi
if [[ "$(uname -m)" != arm64 ]]; then
    echo 'This distribution targets Apple Silicon (arm64).' >&2
    exit 2
fi
mkdir -p "$BUILD_DIR/ModuleCache" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
BUNDLE_IDENTIFIER="org.relaisapp.Relais"
SWIFT_FLAGS=(-O -whole-module-optimization -swift-version 5
    -file-prefix-map "$PROJECT_DIR=Relais"
    -debug-prefix-map "$PROJECT_DIR=Relais")
if [[ "${RELAIS_TESTING:-0}" == 1 ]]; then
    # The test app uses its own sandbox container, never the production container.
    SWIFT_FLAGS+=(-D RELAIS_TESTING)
    BUNDLE_IDENTIFIER="${RELAIS_TEST_BUNDLE_IDENTIFIER:-org.relaisapp.Relais.Testing}"
    if [[ ! "$BUNDLE_IDENTIFIER" =~ ^org[.]relaisapp[.]Relais[.]Testing([.][A-Za-z0-9-]+)*$ ]]; then
        echo 'A test bundle must use the isolated Relais.Testing identifier namespace.' >&2
        exit 2
    fi
fi
SOURCES=()
while IFS= read -r -d '' file; do SOURCES+=("$file"); done < <(find "$PROJECT_DIR/Relais" -name '*.swift' -print0)
if [[ ${#SOURCES[@]} -eq 0 ]]; then echo 'No Swift sources found.' >&2; exit 1; fi
xcrun swiftc "${SWIFT_FLAGS[@]}" \
    -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_DIR/ModuleCache" \
    -framework AppKit -framework SwiftUI -framework ServiceManagement \
    "${SOURCES[@]}" -o "$APP_PATH/Contents/MacOS/Relais"
cp "$PROJECT_DIR/Relais/Info.plist" "$APP_PATH/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$BUNDLE_IDENTIFIER" "$APP_PATH/Contents/Info.plist"
if [[ "${RELAIS_TESTING:-0}" == 1 ]]; then
    /usr/bin/plutil -replace CFBundleDisplayName -string 'Relais — Aperçu' "$APP_PATH/Contents/Info.plist"
fi
if [[ ! -f "$PROJECT_DIR/Relais/Resources/AppIcon.icns" ]]; then
    "$PROJECT_DIR/Scripts/generate-icon.sh"
fi
if [[ -d "$PROJECT_DIR/Relais/Resources" ]]; then
    ditto "$PROJECT_DIR/Relais/Resources" "$APP_PATH/Contents/Resources"
fi
if [[ "${RELAIS_TESTING:-0}" == 1 ]]; then
    # Migration runs before our fixture code. Never let a test identity move the
    # production user's legacy state, even when reusing an old test bundle.
    rm -f "$APP_PATH/Contents/Resources/container-migration.plist"
fi
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
# Local ad-hoc signature, NOT a Developer ID signature and NOT notarization.
codesign --force --sign - --identifier "$BUNDLE_IDENTIFIER" \
    --options runtime --timestamp=none \
    --entitlements "$PROJECT_DIR/Relais/Relais.entitlements" "$APP_PATH"
codesign --verify --strict "$APP_PATH"
echo "Built: $APP_PATH"
echo 'App Sandbox and Hardened Runtime enabled; no network or file exceptions.'
echo 'Signature: local ad-hoc only; not Developer ID signed or Apple notarized.'
