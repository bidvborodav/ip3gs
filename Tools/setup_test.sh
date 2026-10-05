#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/setup.sh"

"$SCRIPT_DIR/bin/ideviceinfo" --version >/dev/null
"$SCRIPT_DIR/bin/afcclient" --version >/dev/null

# Portable means: links only system libraries, nothing from Homebrew or the build tree.
for bin in ideviceinfo afcclient; do
  if otool -L "$SCRIPT_DIR/bin/$bin" | tail -n +2 | grep -Eq '/opt/homebrew|/usr/local|/var/folders|/tmp/'; then
    echo "FAIL: $bin links a non-system library:" >&2
    otool -L "$SCRIPT_DIR/bin/$bin" >&2
    exit 1
  fi
done

echo "PASS: vendored binaries built, respond to --version, and link only system libraries"
