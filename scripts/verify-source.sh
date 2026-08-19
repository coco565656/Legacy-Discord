#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
SOURCE_DIR="$PROJECT_DIR/Discord Lite"
PROJECT_FILE="$PROJECT_DIR/Discord Lite.xcodeproj/project.pbxproj"

plutil -lint "$PROJECT_FILE" "$SOURCE_DIR/Info.plist"

if grep -R -n -E 'api/v6|encoding=json&v=6|SSL_VERIFYPEER, 0|SSL_VERIFYHOST, 0|Loaded token:' "$SOURCE_DIR" \
    --exclude-dir=curl_headers; then
    echo "Legacy endpoint, disabled TLS verification, or token logging found." >&2
    exit 1
fi

for library in libcurl.4.dylib libssl.3.dylib libcrypto.3.dylib; do
    if ! lipo -info "$SOURCE_DIR/$library" | grep -q 'x86_64'; then
        echo "$library does not contain an x86_64 slice." >&2
        exit 1
    fi
done

if command -v xcrun >/dev/null 2>&1 && command -v clang >/dev/null 2>&1; then
    SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
    find "$SOURCE_DIR" -name '*.m' -print0 | xargs -0 clang \
        -fsyntax-only \
        -fno-objc-arc \
        -Wno-deprecated-declarations \
        -Wno-objc-method-access \
        -Wno-incompatible-pointer-types \
        -isysroot "$SDK_PATH" \
        -mmacosx-version-min=10.7 \
        -arch x86_64 \
        -I"$SOURCE_DIR"
fi

echo "Source verification passed."
