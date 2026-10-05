#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin"
mkdir -p "$BIN_DIR"

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
PREFIX="$BUILD_DIR/out"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

# Build-time only: Homebrew supplies the static OpenSSL archives. The shipped
# binaries link them statically, so they carry no /opt/homebrew references.
# The dir below holds only the .a files: with the dylibs beside them the linker
# picks the dylibs, and passing the .a by full path makes libtool nest one
# archive inside another, which drops every libimobiledevice symbol.
BREW_OPENSSL="${OPENSSL_PREFIX:-$(brew --prefix openssl@3)}"
OPENSSL="$BUILD_DIR/openssl-static"
mkdir -p "$OPENSSL/lib"
ln -s "$BREW_OPENSSL/include" "$OPENSSL/include"
ln -s "$BREW_OPENSSL/lib/libssl.a" "$BREW_OPENSSL/lib/libcrypto.a" "$OPENSSL/lib/"

build() {
  local name="$1"; shift
  git clone --depth 1 "https://github.com/libimobiledevice/$name" "$BUILD_DIR/$name"
  (
    cd "$BUILD_DIR/$name"
    ./autogen.sh --prefix="$PREFIX" --disable-shared --enable-static "$@"
    make -j"$(sysctl -n hw.ncpu)"
    make install
  )
}

echo "Building libimobiledevice into $BIN_DIR (this does not touch global installs)..."

build libplist --without-cython
build libimobiledevice-glue
build libtatsu
build libusbmuxd
build libimobiledevice --without-cython \
  openssl_CFLAGS="-I$OPENSSL/include" \
  openssl_LIBS="-L$OPENSSL/lib -lssl -lcrypto"

cp "$PREFIX/bin/ideviceinfo" "$BIN_DIR/ideviceinfo"
cp "$PREFIX/bin/afcclient" "$BIN_DIR/afcclient"
chmod +x "$BIN_DIR/ideviceinfo" "$BIN_DIR/afcclient"

echo "Done. Binaries installed at $BIN_DIR"
