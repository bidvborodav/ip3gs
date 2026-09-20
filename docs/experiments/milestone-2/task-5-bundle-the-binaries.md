# Task 5: Bundle the binaries

**Files:** modify `project.yml`, `Sources/ip3gs/DeviceBridge/DeviceBridge.swift`; add a small test.

- [ ] **Step 1: `project.yml`** — under `targets.ip3gs`, add:

```yaml
    copyFiles:
      - destination: executables
        files:
          - path: Tools/bin/ideviceinfo
            codeSign: true
          - path: Tools/bin/afcclient
            codeSign: true
```

  `executables` is `Contents/MacOS`, the conventional home for helper executables, and
  `codeSign: true` re-signs them with the app's identity so hardened runtime accepts them. The
  build now **requires** `Tools/bin/` to exist — run `./Tools/setup.sh` after a fresh clone (this
  goes in `CLAUDE.md` in Task 8).

- [ ] **Step 2: Resolve from the bundle.** In `DeviceBridge`:

```swift
// Helpers are copied next to the app executable at build time; fall back to the repo path when
// that lookup fails (e.g. a host process that is not the app).
static var bundledBinDir: String {
    Bundle.main.url(forAuxiliaryExecutable: "afcclient")?.deletingLastPathComponent().path
        ?? "Tools/bin"
}

init(binDir: String = DeviceBridge.bundledBinDir, runner: ProcessRunning = SystemProcessRunner()) {
```

- [ ] **Step 3: Build and inspect the product.**

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
  Paste the `otool` output into the Task 8 doc update as the evidence for the done-when line.

- [ ] **Step 4: Prove it runs away from the repo root.**

```bash
APP_ABS="$(pwd)/build/Build/Products/Debug/ip3gs.app"
cd / && open -n "$APP_ABS"
```

  `open` from `/` is the closest scripted stand-in for a Finder launch: the working directory is
  not the repo, so the old relative `Tools/bin` path cannot resolve. The window should show the
  connected phone's photos; if it shows "No device connected" with the phone attached, the helper
  lookup or signing is wrong — check Console for `ip3gs` launch errors before changing code.
  (Return to the worktree directory afterwards; the shell's cwd persists.)

- [ ] **Step 5: Run the full unit suite**, then commit `feat: bundle ideviceinfo and afcclient into the app`.

Back to the [milestone 2 plan](README.md).
