#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
XCODE_PATH=$(xcode-select -p 2>/dev/null || true)
ARTIFACT_DIR="$PROJECT_DIR/artifacts/local-dev"
DERIVED_DATA="$ARTIFACT_DIR/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/DevLocal/Legacy Discord Dev.app"
if [ -z "$XCODE_PATH" ] || [ ! -x "$XCODE_PATH/usr/bin/xcodebuild" ]; then echo "Xcode is not selected. Run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2; exit 1; fi
mkdir -p "$DERIVED_DATA"
echo "Building DevLocal with: $XCODE_PATH"
build_devlocal() {
    xcodebuild -project "$PROJECT_DIR/Discord Lite.xcodeproj" -scheme "Legacy Discord Dev" -configuration DevLocal -sdk macosx -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
}
if ! build_devlocal; then
    echo "DevLocal build failed. Inspect the xcodebuild output above." >&2
    exit 1
fi
if [ ! -d "$APP_PATH" ]; then echo "DevLocal build completed but the expected app was not produced: $APP_PATH" >&2; exit 1; fi
echo "DevLocal app: $APP_PATH"
