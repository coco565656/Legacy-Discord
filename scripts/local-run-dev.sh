#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
APP_PATH="$PROJECT_DIR/artifacts/local-dev/DerivedData/Build/Products/DevLocal/Legacy Discord Dev.app"
FIXTURE="channel-basic"; WINDOW_SIZE="960x640"; BUILD=1
usage() { echo "Usage: $0 [--fixture channel-basic|channel-message-states|channel-layout-text|channel-layout-unbroken|channel-layout-states|channel-layout-attachment|channel-navigation|composer-text|composer-reply|composer-attachment|composer-emoji|composer-mention|composer-typing|composer-sticker] [--window-size 720x520|960x640|1280x800] [--no-build]"; }
while [ "$#" -gt 0 ]; do case "$1" in --fixture) FIXTURE="$2"; shift 2;; --window-size) WINDOW_SIZE="$2"; shift 2;; --no-build) BUILD=0; shift;; -h|--help) usage; exit 0;; *) echo "Unknown option: $1" >&2; usage >&2; exit 2;; esac; done
case "$FIXTURE" in channel-basic|channel-message-states|channel-layout|channel-layout-text|channel-layout-unbroken|channel-layout-states|channel-layout-attachment|channel-navigation|composer-text|composer-reply|composer-attachment|composer-emoji|composer-mention|composer-typing|composer-sticker) ;; *) echo "Unknown fixture: $FIXTURE" >&2; exit 2;; esac
case "$WINDOW_SIZE" in 720x520|960x640|1280x800) ;; *) echo "Unsupported window size: $WINDOW_SIZE" >&2; exit 2;; esac
if [ "$BUILD" -eq 1 ]; then "$SCRIPT_DIR/local-build-dev.sh"; fi
if [ ! -d "$APP_PATH" ]; then echo "DevLocal app not found: $APP_PATH" >&2; exit 1; fi
echo "Launching fixture: $FIXTURE at $WINDOW_SIZE"
open -n "$APP_PATH" --args --fixture "$FIXTURE" --window-size "$WINDOW_SIZE"
echo "DevLocal app: $APP_PATH"
