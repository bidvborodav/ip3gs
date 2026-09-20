# Task 1 — Vendor libimobiledevice binaries

**Axis:** Spike. Independent of all app code; resolves the riskiest unknown
(can we get the binaries running at all, portably) before anything is built.

**Status:** Committed (`2405dfe`). Scripts written; binaries not yet produced
— see [README](README.md#execution-state).

**Files:** create `Tools/setup.sh`, `Tools/setup_test.sh`; modify `.gitignore`.

**Produces:** `Tools/bin/ideviceinfo`, `Tools/bin/afcclient` — executables on
disk, consumed by Task 2 via a `binDir` parameter defaulting to `Tools/bin`.

- [x] **Step 1: `Tools/setup.sh`**

```bash
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
```

- [x] **Step 2:** append `Tools/bin/` to `.gitignore`.

- [x] **Step 3: `Tools/setup_test.sh`** — verifies the script produced working
  binaries, without requiring a device.

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/setup.sh"

"$SCRIPT_DIR/bin/ideviceinfo" --version >/dev/null
"$SCRIPT_DIR/bin/afcclient" --version >/dev/null

echo "PASS: vendored binaries built and respond to --version"
```

- [ ] **Step 4: run it** — `chmod +x Tools/setup.sh Tools/setup_test.sh && ./Tools/setup_test.sh`
  Expected: `PASS: vendored binaries built and respond to --version`

  **Not yet achieved.** Requires `pkg-config` (`brew install pkg-config`);
  `autoconf`, `automake`, and GNU `libtool` are already present. These are
  developer-machine prerequisites, not app dependencies.

- [x] **Step 5: commit** — `feat: add local libimobiledevice vendoring script`

## Open risk

A source build is not automatically portable. Before this task can be called
truly done, the produced binaries need checking for absolute dylib references
(`otool -L Tools/bin/afcclient`) — the shipped app must run on a Mac with no
Homebrew. See [`../architecture.md`](../architecture.md#binary-resolution-and-portability).
