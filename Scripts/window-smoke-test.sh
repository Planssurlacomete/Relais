#!/bin/bash
# AppKit checks in a separate sandboxed testing build and a macOS GUI session.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${RELAIS_BUILD_DIR:-$PROJECT_DIR/.build-cli}"
APP_PATH="${1:-$BUILD_DIR/RelaisTesting.app}"
RELAIS_TESTING=1 "$PROJECT_DIR/Scripts/build.sh" "$APP_PATH"
"$APP_PATH/Contents/MacOS/Relais" --smoke-test
