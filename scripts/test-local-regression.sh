#!/bin/bash

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
ARTIFACT_ROOT="$PROJECT_DIR/artifacts/local-dev/regression"
RUN_ID=$(date +%Y%m%d-%H%M%S)
RUN_DIR="$ARTIFACT_ROOT/$RUN_ID"
QUICK=0
FIXTURE=""
SCREENSHOTS=0
FAILURES=0
LAST_STEP_FAILED=0

usage() {
    echo "Usage: $0 [--quick] [--screenshots] [--fixture NAME]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --quick) QUICK=1; shift ;;
        --screenshots) SCREENSHOTS=1; shift ;;
        --fixture) FIXTURE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

mkdir -p "$RUN_DIR/logs" "$RUN_DIR/screenshots" "$RUN_DIR/crash-reports"
printf 'run_id=%s\ngit_commit=%s\nstarted_at=%s\n' "$RUN_ID" "$(git -C "$PROJECT_DIR" rev-parse --short HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$RUN_DIR/manifest.txt"

run_step() {
    step_name="$1"
    shift
    echo "[$step_name]"
    "$@" > "$RUN_DIR/logs/$step_name.log" 2>&1
    task_result=$?
    if [ "$task_result" -eq 0 ]; then
        LAST_STEP_FAILED=0
        echo "  PASS"
    else
        LAST_STEP_FAILED=1
        echo "  FAIL (log: $RUN_DIR/logs/$step_name.log)"
        FAILURES=$((FAILURES + 1))
    fi
}

if [ -n "$FIXTURE" ]; then
    case "$FIXTURE" in channel-basic|channel-message-states|channel-layout|channel-layout-text|channel-layout-unbroken|channel-layout-states|channel-layout-attachment|channel-navigation|composer-text|composer-reply|composer-attachment|composer-emoji|composer-emoji-picker|composer-mention|composer-typing|composer-sticker|profile-note) FIXTURES="$FIXTURE" ;; *) echo "Unknown fixture: $FIXTURE" >&2; exit 2;; esac
else
    FIXTURES="channel-basic channel-message-states channel-layout-text channel-layout-unbroken channel-layout-states channel-layout-attachment channel-navigation composer-text composer-reply composer-attachment composer-emoji composer-emoji-picker composer-mention composer-typing composer-sticker profile-note"
fi

SIZES="960x640"
if [ "$SCREENSHOTS" -eq 1 ]; then SIZES="720x520 960x640 1280x800"; fi

run_step diff-check git -C "$PROJECT_DIR" diff --check
if [ "$QUICK" -eq 0 ]; then run_step verify-source "$SCRIPT_DIR/verify-source.sh"; fi
run_step local-build-dev "$SCRIPT_DIR/local-build-dev.sh"
run_step local-build-login-preview "$SCRIPT_DIR/local-build-login-preview.sh"

if [ "$LAST_STEP_FAILED" -eq 1 ]; then
    echo "[fixtures] NOT RUN (a required build failed)"
    FIXTURES=""
fi

CRASH_DIR="${HOME}/Library/Logs/DiagnosticReports"
for fixture_name in $FIXTURES; do
    for window_size in $SIZES; do
        screenshot_path="$RUN_DIR/screenshots/$fixture_name-$window_size.png"
        run_step "fixture-$fixture_name-$window_size" "$SCRIPT_DIR/capture-ui-dev.sh" "$fixture_name" --window-size "$window_size" --no-build --output "$screenshot_path"
        if [ -f "$screenshot_path" ]; then
            printf 'fixture=%s screenshot=%s size=%s theme=default scale=system\n' "$fixture_name" "$screenshot_path" "$window_size" >> "$RUN_DIR/manifest.txt"
        fi
    done
done

if [ -d "$CRASH_DIR" ]; then
    find "$CRASH_DIR" -maxdepth 1 -type f \( -name 'Legacy Discord Dev*.ips' -o -name 'Legacy Discord Dev*.crash' \) -newer "$RUN_DIR/manifest.txt" -exec cp {} "$RUN_DIR/crash-reports/" \; 2>/dev/null || true
fi
if find "$RUN_DIR/crash-reports" -type f | grep -q .; then
    echo "[crash-report] FAIL (saved under $RUN_DIR/crash-reports)"
    FAILURES=$((FAILURES + 1))
else
    echo "[crash-report] PASS"
fi

echo
echo "Artifacts: $RUN_DIR"
if [ "$FAILURES" -eq 0 ]; then
    echo "Regression result: PASS"
    exit 0
fi
echo "Regression result: FAIL ($FAILURES step(s))"
exit 1
