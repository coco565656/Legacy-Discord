#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
REMOTE_HOST=MacBook
OUTPUT_PATH=""
REMOTE_CAPTURE_PATH=""

usage() {
    echo "Usage: $0 [--host SSH_ALIAS] [--output PATH]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --host) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; REMOTE_HOST="$2"; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; OUTPUT_PATH="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

case "$REMOTE_HOST" in
    *[!A-Za-z0-9._-]*|'') echo "Invalid SSH host alias" >&2; exit 2 ;;
esac

if [ -z "$OUTPUT_PATH" ]; then
    OUTPUT_PATH="$PROJECT_DIR/artifacts/snow-leopard/screenshots/$(date +%Y%m%d-%H%M%S)-$$.png"
fi
case "$OUTPUT_PATH" in
    /*) ;;
    *) OUTPUT_PATH="$PROJECT_DIR/$OUTPUT_PATH" ;;
esac
mkdir -p "$(dirname "$OUTPUT_PATH")"

cleanup() {
    if [ -n "$REMOTE_CAPTURE_PATH" ]; then
        ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST" \
            "rm -f '$REMOTE_CAPTURE_PATH'" >/dev/null 2>&1 || true
    fi
}

REMOTE_CAPTURE_PATH=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST" '
    capture_path="/tmp/legacy-discord-screenshot-$(date +%Y%m%d-%H%M%S)-$$.png"
    /usr/sbin/screencapture -x "$capture_path" || exit 1
    [ -s "$capture_path" ] || exit 1
    printf "%s\n" "$capture_path"
')
if [[ ! "$REMOTE_CAPTURE_PATH" =~ ^/tmp/legacy-discord-screenshot-[0-9]{8}-[0-9]{6}-[0-9]+\.png$ ]]; then
    echo "Unexpected remote screenshot path" >&2
    exit 1
fi
trap cleanup EXIT

scp -q "$REMOTE_HOST:$REMOTE_CAPTURE_PATH" "$OUTPUT_PATH"
if ! file -b "$OUTPUT_PATH" | grep -q '^PNG image'; then
    echo "Downloaded screenshot is not a PNG: $OUTPUT_PATH" >&2
    exit 1
fi
echo "Screenshot: $OUTPUT_PATH"
