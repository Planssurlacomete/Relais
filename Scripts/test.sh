#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${RELAIS_BUILD_DIR:-$PROJECT_DIR/.build-cli}"
mkdir -p "$BUILD_DIR/ModuleCache"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SOURCES=()
for directory in Models Persistence; do
    while IFS= read -r -d '' file; do SOURCES+=("$file"); done < <(find "$PROJECT_DIR/Relais/$directory" -name '*.swift' -print0)
done
while IFS= read -r -d '' file; do SOURCES+=("$file"); done < <(find "$PROJECT_DIR/Tests" -maxdepth 1 -name '*.swift' -print0)
xcrun swiftc -parse-as-library -swift-version 5 \
    -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_DIR/ModuleCache" \
    "${SOURCES[@]}" -o "$BUILD_DIR/RelaisTests"
"$BUILD_DIR/RelaisTests"
