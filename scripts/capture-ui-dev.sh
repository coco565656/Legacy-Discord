#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
FIXTURE="channel-basic"
WINDOW_SIZE="960x640"
BUILD=1
DIAGNOSTICS=0
OUTPUT_PATH=""
OUTPUT_DIR="$PROJECT_DIR/artifacts/local-dev/screenshots"
usage() { echo "Usage: $0 [fixture] [--window-size 720x520|960x640|1280x800] [--no-build] [--diagnostics] [--output PATH]"; }
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-build) BUILD=0; shift ;;
        --window-size) WINDOW_SIZE="$2"; shift 2 ;;
        --diagnostics) DIAGNOSTICS=1; shift ;;
        --output) OUTPUT_PATH="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) FIXTURE="$1"; shift ;;
    esac
done
case "$FIXTURE" in channel-basic|channel-message-states|channel-layout|channel-layout-text|channel-layout-unbroken|channel-layout-states|channel-layout-attachment|channel-navigation|composer-text|composer-reply|composer-attachment|composer-emoji|composer-emoji-picker|composer-mention|composer-typing|composer-sticker|profile-note) ;; *) echo "Unknown fixture: $FIXTURE" >&2; exit 2;; esac
case "$WINDOW_SIZE" in 720x520|960x640|1280x800) ;; *) echo "Unsupported window size: $WINDOW_SIZE" >&2; exit 2;; esac
if [ -z "$OUTPUT_PATH" ]; then OUTPUT_PATH="$OUTPUT_DIR/$FIXTURE.png"; fi
case "$OUTPUT_PATH" in
    /*) ;;
    *) OUTPUT_PATH="$PROJECT_DIR/$OUTPUT_PATH" ;;
esac
mkdir -p "$(dirname "$OUTPUT_PATH")"
if [ "$BUILD" -eq 1 ]; then "$SCRIPT_DIR/local-build-dev.sh"; fi
APP_PATH="$PROJECT_DIR/artifacts/local-dev/DerivedData/Build/Products/DevLocal/Legacy Discord Dev.app"
APP_ARGS=(--fixture "$FIXTURE" --window-size "$WINDOW_SIZE" --screenshot "$OUTPUT_PATH")
if [ "$DIAGNOSTICS" -eq 1 ]; then APP_ARGS+=(--write-sanitized-ui-diagnostics); fi
PREVIOUS_FILE_ID=""
if [ -f "$OUTPUT_PATH" ]; then PREVIOUS_FILE_ID=$(stat -f '%i' "$OUTPUT_PATH"); fi
screenshot_was_written() {
    if [ ! -f "$OUTPUT_PATH" ]; then return 1; fi
    CURRENT_FILE_ID=$(stat -f '%i' "$OUTPUT_PATH")
    [ -z "$PREVIOUS_FILE_ID" ] || [ "$CURRENT_FILE_ID" != "$PREVIOUS_FILE_ID" ]
}
open -W -n "$APP_PATH" --args "${APP_ARGS[@]}" &
OPEN_PID=$!
attempt=0
while ! screenshot_was_written && [ "$attempt" -lt 80 ]; do
    if ! kill -0 "$OPEN_PID" 2>/dev/null; then break; fi
    sleep 0.25
    attempt=$((attempt + 1))
done
if ! screenshot_was_written; then
    SAMPLE_PATH="$(dirname "$OUTPUT_PATH")/$(basename "$OUTPUT_PATH" .png).sample.txt"
    APP_PROCESS_ID=$(pgrep -x "Legacy Discord Dev" | tail -1 || true)
    if [ -n "$APP_PROCESS_ID" ]; then
        sample "$APP_PROCESS_ID" 5 -file "$SAMPLE_PATH" >/dev/null 2>&1 || true
        kill "$APP_PROCESS_ID" 2>/dev/null || true
    fi
    wait "$OPEN_PID" 2>/dev/null || true
    echo "Fixture screenshot was not written within 20 seconds: $OUTPUT_PATH" >&2
    echo "Sample: $SAMPLE_PATH" >&2
    exit 1
fi

# The application writes the PNG immediately before terminating. Waiting for
# that termination prevents the next fixture from racing the previous process
# while AppKit and NSSplitView persist window state.
attempt=0
while kill -0 "$OPEN_PID" 2>/dev/null && [ "$attempt" -lt 80 ]; do
    sleep 0.25
    attempt=$((attempt + 1))
done
if kill -0 "$OPEN_PID" 2>/dev/null; then
    SAMPLE_PATH="$(dirname "$OUTPUT_PATH")/$(basename "$OUTPUT_PATH" .png).sample.txt"
    APP_PROCESS_ID=$(pgrep -x "Legacy Discord Dev" | tail -1 || true)
    if [ -n "$APP_PROCESS_ID" ]; then sample "$APP_PROCESS_ID" 5 -file "$SAMPLE_PATH" >/dev/null 2>&1 || true; fi
    echo "Fixture application did not terminate after capture. Sample: $SAMPLE_PATH" >&2
    exit 1
fi
if ! wait "$OPEN_PID"; then
    echo "Fixture application exited unsuccessfully after writing: $OUTPUT_PATH" >&2
    exit 1
fi
echo "Screenshot: $OUTPUT_PATH"
