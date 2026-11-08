#!/bin/bash
# Native icon checks, without showing windows or opening a production data store.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${RELAIS_BUILD_DIR:-$PROJECT_DIR/.build-cli}"
mkdir -p "$BUILD_DIR/ModuleCache"
xcrun swiftc -parse-as-library -swift-version 5 \
    -target arm64-apple-macosx14.0 -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -module-cache-path "$BUILD_DIR/ModuleCache" \
    "$PROJECT_DIR/Relais/Branding/RelaisIcon.swift" \
    "$PROJECT_DIR/Tests/Branding/IconRenderingTests.swift" \
    -o "$BUILD_DIR/RelaisIconTests"
"$BUILD_DIR/RelaisIconTests" "$@"
