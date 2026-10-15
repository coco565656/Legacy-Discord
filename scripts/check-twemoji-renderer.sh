#!/bin/sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CHECK_ROOT=$(mktemp -d /tmp/legacy-twemoji-check.XXXXXX)
trap 'rm -rf "$CHECK_ROOT"' EXIT
CHECK_APP="$CHECK_ROOT/TwemojiCheck.app"
mkdir -p "$CHECK_APP/Contents/MacOS" "$CHECK_APP/Contents/Resources"
ln -s "$PROJECT_DIR/Discord Lite/Twemoji72" "$CHECK_APP/Contents/Resources/Twemoji72"
cat > "$CHECK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TwemojiCheck</string>
<key>CFBundleIdentifier</key><string>org.legacydiscord.twemoji-check</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
CHECK_COMPILER=clang
set --
if [ -d /Developer/SDKs/MacOSX10.6.sdk ]; then
    CHECK_COMPILER=/Developer/usr/bin/clang
    set -- -isysroot /Developer/SDKs/MacOSX10.6.sdk -mmacosx-version-min=10.6
fi
"$CHECK_COMPILER" "$@" -framework Cocoa -I"$PROJECT_DIR/Discord Lite" \
    "$PROJECT_DIR/Discord Lite/DLTwemojiRenderer.m" \
    "$PROJECT_DIR/scripts/check-twemoji-renderer.m" \
    -o "$CHECK_APP/Contents/MacOS/TwemojiCheck"
"$CHECK_APP/Contents/MacOS/TwemojiCheck"
