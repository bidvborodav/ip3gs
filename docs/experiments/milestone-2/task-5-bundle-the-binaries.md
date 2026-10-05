# Task 5: Bundle the binaries

**Files:** modify `project.yml`, `Sources/ip3gs/DeviceBridge/DeviceBridge.swift`; add a small test.

- [x] **Step 1: `project.yml`** — under `targets.ip3gs.sources`, add:

```yaml
      - path: Tools/bin/ideviceinfo
        buildPhase:
          copyFiles:
            destination: executables
        attributes: [CodeSignOnCopy]
      - path: Tools/bin/afcclient
        buildPhase:
          copyFiles:
            destination: executables
        attributes: [CodeSignOnCopy]
```

  > **Deviation from the plan as first written.** The plan said to use a target-level
  > `copyFiles:` key with `codeSign: true`. xcodegen 2.44.1 **silently ignores** that key: the
  > build succeeded and the app simply had no helpers. Caught by listing `Contents/MacOS` after the
  > build, not by the build. The copy phase is declared on the *source entries* instead.

  `executables` is `Contents/MacOS`, the conventional home for helper executables, and
  `CodeSignOnCopy` re-signs them with the app's identity so hardened runtime accepts them. The
  build now **requires** `Tools/bin/` to exist — run `./Tools/setup.sh` after a fresh clone.

- [x] **Step 2: Resolve from the bundle.** In `DeviceBridge`:

```swift
// Helpers are copied next to the app executable at build time; fall back to the repo path when
// that lookup fails (e.g. a host process that is not the app).
static var bundledBinDir: String {
    Bundle.main.url(forAuxiliaryExecutable: "afcclient")?.deletingLastPathComponent().path
        ?? "Tools/bin"
}

init(binDir: String = DeviceBridge.bundledBinDir, runner: ProcessRunning = SystemProcessRunner()) {
```

- [x] **Step 3: Build and inspect the product.**

```bash
xcodegen generate
xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -configuration Debug -derivedDataPath build build
APP=build/Build/Products/Debug/ip3gs.app
ls -l $APP/Contents/MacOS                      # ip3gs, ideviceinfo, afcclient — all executable
otool -L $APP/Contents/MacOS/ideviceinfo $APP/Contents/MacOS/afcclient   # system libs only
codesign --verify --deep --strict $APP && echo signed-ok
```

  Expected: both helpers present and executable; `otool` lists only `/usr/lib` and
  `/System/Library` paths (no `/opt/homebrew`, `/usr/local`, `/var/folders`); `signed-ok`.
  **Observed (2026-09-20):** `Contents/MacOS` held `ip3gs`, `ideviceinfo`, `afcclient`. Both
  helpers list exactly `/usr/lib/libSystem.B.dylib`,
  `/System/Library/Frameworks/SystemConfiguration.framework/…` and
  `/System/Library/Frameworks/CoreFoundation.framework/…` — nothing else. `codesign --verify
  --deep --strict` passed; the helpers carry an ad-hoc signature (they were re-signed on copy).

- [x] **Step 4: Prove it runs away from the repo root.**

```bash
APP_ABS="$(pwd)/build/Build/Products/Debug/ip3gs.app"
cd / && open -n "$APP_ABS"
```

  `open` from `/` is the closest scripted stand-in for a Finder launch: the working directory is
  not the repo, so the old relative `Tools/bin` path cannot resolve. The window should show the
  connected phone's photos; if it shows "No device connected" with the phone attached, the helper
  lookup or signing is wrong — check Console for `ip3gs` launch errors before changing code.
  **Observed:** `ps` showed the app's parent as launchd (pid 1) and `lsof` showed its cwd as `/`;
  it found the phone and loaded the photos. (`open` alone is enough — LaunchServices starts apps
  with cwd `/` — so no `cd /` is needed.)

- [x] **Step 5: Run the full unit suite**, then commit `feat: bundle ideviceinfo and afcclient into the app`.

Back to the [milestone 2 plan](README.md).
