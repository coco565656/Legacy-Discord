#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")

REMOTE_HOST="mountainlion"
REMOTE_DIR="Developer/legacy-discordClient-remote"
CONFIGURATION="Debug"
SYNC_SOURCE=1
RUN_AFTER_BUILD=0

usage() {
    printf '%s\n' \
        "Usage: $0 [options]" \
        "" \
        "Options:" \
        "  --host NAME       SSH host alias (default: mountainlion)" \
        "  --remote-dir DIR  Path relative to remote home" \
        "                    (default: Developer/legacy-discordClient-remote)" \
        "  --release         Build the Release configuration" \
        "  --no-sync         Rebuild the source already present on the remote Mac" \
        "  --run             Open the built app on the remote Mac after success" \
        "  -h, --help        Show this help"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --host)
            REMOTE_HOST="$2"
            shift 2
            ;;
        --remote-dir)
            REMOTE_DIR="$2"
            shift 2
            ;;
        --release)
            CONFIGURATION="Release"
            shift
            ;;
        --no-sync)
            SYNC_SOURCE=0
            shift
            ;;
        --run)
            RUN_AFTER_BUILD=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! printf '%s' "$REMOTE_HOST" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    printf 'Unsafe SSH host alias: %s\n' "$REMOTE_HOST" >&2
    exit 2
fi

if ! printf '%s' "$REMOTE_DIR" | grep -Eq '^[A-Za-z0-9._/-]+$'; then
    printf 'Remote directory contains unsupported characters: %s\n' "$REMOTE_DIR" >&2
    exit 2
fi

case "/$REMOTE_DIR/" in
    //*|*/../*|*/./*)
        printf 'Remote directory must be a safe path relative to the remote home: %s\n' "$REMOTE_DIR" >&2
        exit 2
        ;;
esac

# Mountain Lion's older sshd can reject multiplexed session channels with
# "Master refused session request: Permission denied" even though ordinary SSH
# sessions work. Independent connections are more reliable on OS X 10.8.
SSH_RSH="ssh -o ConnectTimeout=15"

printf 'Checking remote build environment...\n'
$SSH_RSH "$REMOTE_HOST" '
    set -e
    printf "OS X: "
    sw_vers -productVersion
    printf "Architecture: "
    uname -m
    xcodebuild -version
    xcode-select -print-path
    xcodebuild -showsdks
'

if [ "$SYNC_SOURCE" -eq 1 ]; then
    printf 'Creating remote project directory: ~/%s\n' "$REMOTE_DIR"
    $SSH_RSH "$REMOTE_HOST" "mkdir -p \"\$HOME/$REMOTE_DIR\""

    printf 'Synchronizing source...\n'
    rsync \
        -az \
        -e "$SSH_RSH" \
        --exclude '.git/' \
        --exclude 'artifacts/' \
        --exclude 'build/' \
        --exclude 'DerivedData/' \
        --exclude '*.xcuserstate' \
        "$PROJECT_DIR/" \
        "$REMOTE_HOST:$REMOTE_DIR/"
fi

# Keep products from different legacy Macs separate when --host is used.
ARTIFACT_DIR="$PROJECT_DIR/artifacts/$REMOTE_HOST/$CONFIGURATION"
mkdir -p "$ARTIFACT_DIR"
LOCAL_LOG="$ARTIFACT_DIR/xcodebuild.log"

printf 'Building %s on %s...\n' "$CONFIGURATION" "$REMOTE_HOST"
set +e
$SSH_RSH "$REMOTE_HOST" "
    set -o pipefail 2>/dev/null || true
    cd \"\$HOME/$REMOTE_DIR\"
    xcodebuild \\
      -project \"Discord Lite.xcodeproj\" \\
      -scheme \"Discord Lite\" \\
      -configuration \"$CONFIGURATION\" \\
      -sdk macosx \\
      ARCHS=x86_64 \\
      ONLY_ACTIVE_ARCH=NO \\
      MACOSX_DEPLOYMENT_TARGET=10.7 \\
      CODE_SIGN_IDENTITY= \\
      CODE_SIGNING_REQUIRED=NO \\
      OBJROOT=\"\$PWD/build/obj\" \\
      SYMROOT=\"\$PWD/build\" \\
      clean build
" 2>&1 | tee "$LOCAL_LOG"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

if [ "$BUILD_STATUS" -ne 0 ]; then
    printf '\nRemote build failed. Full log: %s\n' "$LOCAL_LOG" >&2
    exit "$BUILD_STATUS"
fi

printf 'Downloading build products...\n'
rsync \
    -az \
    -e "$SSH_RSH" \
    "$REMOTE_HOST:$REMOTE_DIR/build/$CONFIGURATION/" \
    "$ARTIFACT_DIR/"

if [ "$RUN_AFTER_BUILD" -eq 1 ]; then
    printf 'Opening the app on %s...\n' "$REMOTE_HOST"
    $SSH_RSH "$REMOTE_HOST" "
        APP_PATH=\"\$HOME/$REMOTE_DIR/build/$CONFIGURATION/Discord Lite.app\"
        # Finder reuses an already-running application even when its bundle was
        # rebuilt in place. Quit that process first so --run always tests the
        # binary produced by this build, rather than leaving the old image open.
        if pgrep -x \"Discord Lite\" >/dev/null; then
            /usr/bin/osascript -e 'tell application \"Discord Lite\" to quit' >/dev/null 2>&1 || true
            WAIT_COUNT=0
            while pgrep -x \"Discord Lite\" >/dev/null && [ \"\$WAIT_COUNT\" -lt 30 ]; do
                sleep 0.1
                WAIT_COUNT=\$((WAIT_COUNT + 1))
            done
        fi
        if pgrep -x Finder >/dev/null && /usr/bin/osascript \\
            -e 'on run argv' \\
            -e 'set appAlias to POSIX file (item 1 of argv)' \\
            -e 'tell application \"Finder\" to open appAlias' \\
            -e 'end run' \\
            \"\$APP_PATH\"; then
            exit 0
        fi
        FINDER_PID=\$(pgrep -x Finder | head -n 1)
        if [ -n \"\$FINDER_PID\" ] && launchctl bsexec \"\$FINDER_PID\" /usr/bin/open \"\$APP_PATH\"; then
            exit 0
        fi
        printf 'Warning: Finder Aqua session was not available; using ordinary open.\\n' >&2
        /usr/bin/open \"\$APP_PATH\"
    "
fi

printf '\nRemote build succeeded.\n'
printf 'App: %s/Discord Lite.app\n' "$ARTIFACT_DIR"
printf 'Log: %s\n' "$LOCAL_LOG"
