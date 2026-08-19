#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

exec "$SCRIPT_DIR/remote-build-mountainlion.sh" \
    --host mavericks \
    --remote-dir Developer/legacy-discordClient-mavericks \
    "$@"
