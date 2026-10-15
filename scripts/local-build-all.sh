#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

"$SCRIPT_DIR/local-build-dev.sh"
"$SCRIPT_DIR/local-build-login-preview.sh"

echo "Built fixture app: $SCRIPT_DIR/../artifacts/local-dev/DerivedData/Build/Products/DevLocal/Legacy Discord Dev.app"
echo "Built login preview: $SCRIPT_DIR/../artifacts/local-login-preview/products/Legacy Discord.app"
