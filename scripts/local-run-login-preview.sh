#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
APP_PATH="$PROJECT_DIR/artifacts/local-login-preview/products/Legacy Discord.app"
BUILD=1

usage() { echo "Usage: $0 [--no-build]"; }
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-build) BUILD=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$BUILD" -eq 1 ]; then "$SCRIPT_DIR/local-build-login-preview.sh"; fi
if [ ! -d "$APP_PATH" ]; then echo "Local login preview was not found: $APP_PATH" >&2; exit 1; fi
if ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
    echo "Rosetta is required to run this x86_64 login preview on Apple Silicon." >&2
    exit 1
fi

echo "Launching local login preview: $APP_PATH"
open -n "$APP_PATH"
