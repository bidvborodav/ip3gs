#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/setup.sh"

"$SCRIPT_DIR/bin/ideviceinfo" --version >/dev/null
"$SCRIPT_DIR/bin/afcclient" --version >/dev/null

echo "PASS: vendored binaries built and respond to --version"
