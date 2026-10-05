# Task 0: Worktree baseline

**Files:** none tracked.

- [x] **Step 1: Give the worktree its binaries.** `Tools/bin/` is gitignored, so a fresh
  worktree has none. Copy from the main checkout (built by `Tools/setup.sh`):

```bash
cp -R /Users/dr.reddys/Documents/GitHub/ip3gs/Tools/bin Tools/bin
otool -L Tools/bin/afcclient Tools/bin/ideviceinfo   # system libraries only
```

- [x] **Step 2: Generate the project and run the baseline.**

```bash
xcodegen generate
xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test
```

Expected: `** TEST SUCCEEDED **`, 23 tests, the 5 `DeviceIntegrationTests` skipped.

- [x] **Step 3: Note the Swift language mode.** `xcodebuild -showBuildSettings | grep SWIFT_VERSION`.
  If it is 6, the `Sendable` annotations in Task 3b are errors, not warnings — fix them, do not
  silence them.

Back to the [milestone 2 plan](README.md).
