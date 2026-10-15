#!/bin/bash
#
# Build the Release app on the Snow Leopard test Mac (Xcode 4.2), sign it with
# the local "Legacy Discord Dev" identity and optionally relaunch it.
#
# Signing matters for testing: the Keychain remembers "Always Allow" per code
# signature. An unsigned binary changes on every build, so the Keychain asked
# again after each rebuild; a stable self-signed identity keeps the approval.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")

REMOTE_HOST="MacBook"
REMOTE_DIR="Developer/legacy-discordClient-ui-debug"
SIGN_IDENTITY="Legacy Discord Dev"
RUN_AFTER_BUILD=0
SETUP_SIGNING=0

usage() {
    printf '%s\n' \
        "Usage: $0 [options]" \
        "" \
        "Options:" \
        "  --host NAME       SSH host alias (default: MacBook)" \
        "  --remote-dir DIR  Path relative to the remote home" \
        "                    (default: Developer/legacy-discordClient-ui-debug)" \
        "  --setup-signing   Create the self-signed \"$SIGN_IDENTITY\" identity in a" \
        "                    dedicated keychain on the remote Mac (once)" \
        "  --run             Quit and reopen the app after a successful build" \
        "  -h, --help        Show this help"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --host) REMOTE_HOST="$2"; shift 2 ;;
        --remote-dir) REMOTE_DIR="$2"; shift 2 ;;
        --setup-signing) SETUP_SIGNING=1; shift ;;
        --run) RUN_AFTER_BUILD=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
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

SSH="ssh -o BatchMode=yes -o ConnectTimeout=15"
# The signing keychain and its random password live only on the remote Mac,
# readable by that user alone; the login keychain is not modified.
SIGNING_DIR='$HOME/Library/LegacyDiscordSigning'

if [ "$SETUP_SIGNING" -eq 1 ]; then
    printf 'Creating the signing identity on %s...\n' "$REMOTE_HOST"
    $SSH "$REMOTE_HOST" "
        set -e
        D=$SIGNING_DIR
        mkdir -p \"\$D\"; chmod 700 \"\$D\"; cd \"\$D\"
        [ -f pass ] || { openssl rand -hex 24 > pass; chmod 600 pass; }
        printf '%s\n' '[ req ]' 'distinguished_name = dn' 'x509_extensions = ext' 'prompt = no' \
            '[ dn ]' 'CN = $SIGN_IDENTITY' \
            '[ ext ]' 'basicConstraints = critical,CA:false' \
            'keyUsage = critical,digitalSignature' 'extendedKeyUsage = critical,codeSigning' > cert.cnf
        openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cert.cnf 2>/dev/null
        chmod 600 key.pem
        openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -passout file:pass -name '$SIGN_IDENTITY'
        [ -f signing.keychain ] || security create-keychain -p \"\$(cat pass)\" \"\$D/signing.keychain\"
        security unlock-keychain -p \"\$(cat pass)\" \"\$D/signing.keychain\"
        security set-keychain-settings \"\$D/signing.keychain\"
        security import id.p12 -k \"\$D/signing.keychain\" -P \"\$(cat pass)\" -T /usr/bin/codesign
        rm -f key.pem id.p12
    "
fi

printf 'Synchronizing tracked sources to %s:~/%s...\n' "$REMOTE_HOST" "$REMOTE_DIR"
# Only files git knows about, so stray local copies never reach the build.
(cd "$PROJECT_DIR" && git ls-files -z) | rsync -a --from0 --files-from=- -e "$SSH" \
    "$PROJECT_DIR/" "$REMOTE_HOST:$REMOTE_DIR/"

ARTIFACT_DIR="$PROJECT_DIR/artifacts/snow-leopard"
mkdir -p "$ARTIFACT_DIR"
LOCAL_LOG="$ARTIFACT_DIR/xcodebuild.log"

printf 'Building Release on %s...\n' "$REMOTE_HOST"
set +e
$SSH "$REMOTE_HOST" "
    cd \"\$HOME/$REMOTE_DIR\" || exit 1
    D=\"\$PWD\"
    # Xcode 4.2 cannot compile the XIBs; the compatible nibs already in the
    # bundle are kept and the UI is built in code.
    xcodebuild -project 'Discord Lite.xcodeproj' -target 'Discord Lite' -configuration Release \
        ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO SDKROOT=macosx10.6 MACOSX_DEPLOYMENT_TARGET=10.6 \
        GCC_VERSION=com.apple.compilers.llvm.clang.1_0 'EXCLUDED_SOURCE_FILE_NAMES=*.xib' \
        GCC_PREPROCESSOR_DEFINITIONS= LIBRARY_SEARCH_PATHS=\"\$D\" \
        OBJROOT=\"\$D/build-production/obj\" SYMROOT=\"\$D/build-production\" \
        CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO build
" > "$LOCAL_LOG" 2>&1
BUILD_STATUS=$?
set -e
grep -E 'error:|BUILD (SUCCEEDED|FAILED)' "$LOCAL_LOG" || true
if [ "$BUILD_STATUS" -ne 0 ]; then
    printf 'Remote build failed. Full log: %s\n' "$LOCAL_LOG" >&2
    exit "$BUILD_STATUS"
fi

printf 'Signing with "%s"...\n' "$SIGN_IDENTITY"
$SSH "$REMOTE_HOST" "
    set -e
    D=$SIGNING_DIR
    if [ ! -f \"\$D/signing.keychain\" ]; then
        printf 'No signing keychain; run with --setup-signing once. The app stays unsigned.\n' >&2
        exit 0
    fi
    security unlock-keychain -p \"\$(cat \"\$D/pass\")\" \"\$D/signing.keychain\"
    APP=\"\$HOME/$REMOTE_DIR/build-production/Release/Legacy Discord.app\"
    codesign -f -s '$SIGN_IDENTITY' --keychain \"\$D/signing.keychain\" \"\$APP\"
    codesign -v \"\$APP\"
"

if [ "$RUN_AFTER_BUILD" -eq 1 ]; then
    printf 'Relaunching the app on %s...\n' "$REMOTE_HOST"
    $SSH "$REMOTE_HOST" "
        /usr/bin/osascript -e 'tell application \"Legacy Discord\" to quit' >/dev/null 2>&1 || killall 'Legacy Discord' 2>/dev/null || true
        sleep 2
        killall 'Legacy Discord' 2>/dev/null || true
        open \"\$HOME/$REMOTE_DIR/build-production/Release/Legacy Discord.app\"
    "
fi

printf 'Remote build succeeded. Log: %s\n' "$LOCAL_LOG"
