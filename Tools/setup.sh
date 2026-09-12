#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin"
mkdir -p "$BIN_DIR"

REPO_URL="https://github.com/libimobiledevice/libimobiledevice"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "Building libimobiledevice into $BIN_DIR (this does not touch global installs)..."

git clone --depth 1 "$REPO_URL" "$BUILD_DIR/libimobiledevice"
cd "$BUILD_DIR/libimobiledevice"
./autogen.sh --prefix="$BUILD_DIR/out"
make -j"$(sysctl -n hw.ncpu)"
make install

cp "$BUILD_DIR/out/bin/ideviceinfo" "$BIN_DIR/ideviceinfo"
cp "$BUILD_DIR/out/bin/afcclient" "$BIN_DIR/afcclient"
chmod +x "$BIN_DIR/ideviceinfo" "$BIN_DIR/afcclient"

echo "Done. Binaries installed at $BIN_DIR"
