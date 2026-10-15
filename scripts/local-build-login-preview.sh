#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
XCODE_PATH=$(xcode-select -p 2>/dev/null || true)
ARTIFACT_DIR="$PROJECT_DIR/artifacts/local-login-preview"
DERIVED_DATA="$ARTIFACT_DIR/DerivedData"
PRODUCT_DIR="$ARTIFACT_DIR/products"
APP_PATH="$PRODUCT_DIR/Legacy Discord.app"

if [ -z "$XCODE_PATH" ] || [ ! -x "$XCODE_PATH/usr/bin/xcodebuild" ]; then
    echo "Xcode is not selected. Run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

mkdir -p "$DERIVED_DATA" "$PRODUCT_DIR"

# CONFIGURATION_BUILD_DIR is outside DerivedData, so modern Xcode does not
# remove resources that were deleted from the project. Recreate only this
# generated bundle; previous Desktop checkpoints are intentionally untouched.
case "$APP_PATH" in
    "$PRODUCT_DIR"/*.app) ;;
    *)
        echo "Refusing to replace an unexpected application path: $APP_PATH" >&2
        exit 1
        ;;
esac
if [ -e "$APP_PATH" ]; then
    rm -rf "$APP_PATH"
fi

echo "Building local login preview with: $XCODE_PATH"
echo "This preview uses the production login path, x86_64, and an Xcode-only 12.0 deployment override."

if ! xcodebuild -project "$PROJECT_DIR/Discord Lite.xcodeproj" -scheme "Discord Lite" -configuration Debug -sdk macosx -derivedDataPath "$DERIVED_DATA" CONFIGURATION_BUILD_DIR="$PRODUCT_DIR" MACOSX_DEPLOYMENT_TARGET=12.0 GCC_PREPROCESSOR_DEFINITIONS='$(inherited) LEGACY_DISCORD_UI_DIAGNOSTICS=1' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build; then
    echo "Local login preview build failed. Inspect the xcodebuild output above." >&2
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Build completed but the expected app was not produced: $APP_PATH" >&2
    exit 1
fi

echo "Local login preview: $APP_PATH"
file "$APP_PATH/Contents/MacOS/Legacy Discord"
