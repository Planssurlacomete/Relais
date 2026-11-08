#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${RELAIS_BUILD_DIR:-$PROJECT_DIR/.build-cli}"
mkdir -p "$BUILD_DIR/ModuleCache" "$PROJECT_DIR/Relais/Resources"
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx14.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -module-cache-path "$BUILD_DIR/ModuleCache" \
    "$PROJECT_DIR/Relais/Branding/RelaisIcon.swift" \
    "$PROJECT_DIR/Scripts/GenerateIcon.swift" -o "$BUILD_DIR/GenerateIcon"
"$BUILD_DIR/GenerateIcon" "$BUILD_DIR/Relais.iconset"
cp "$BUILD_DIR/AppIcon.icns" "$PROJECT_DIR/Relais/Resources/AppIcon.icns"
