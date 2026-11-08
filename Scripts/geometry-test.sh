#!/bin/bash
# Tests the real window controller, using a hidden panel and disposable data.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${RELAIS_BUILD_DIR:-$PROJECT_DIR/.build-cli}"
mkdir -p "$BUILD_DIR/ModuleCache"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -parse-as-library -swift-version 5 \
    -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_DIR/ModuleCache" \
    "$PROJECT_DIR/Relais/Models/RelayModels.swift" \
    "$PROJECT_DIR/Relais/Persistence/ProjectStore.swift" \
    "$PROJECT_DIR/Relais/Window/FloatingPanelController.swift" \
    "$PROJECT_DIR/Tests/WindowGeometry/WindowGeometryTests.swift" \
    -o "$BUILD_DIR/RelaisGeometryTests"
"$BUILD_DIR/RelaisGeometryTests"
