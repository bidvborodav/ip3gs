# Task 6: Verify on the real device and look at the window

Hardware is attached now (`ideviceinfo` reports iOS 6.1.6). No code unless a check fails.

> **Results, as done (2026-09-20).**
> - **Timing (Step 1).** Two cold runs of the integration test: **152 s + 8 s = 160 s**, then
>   **74 s + 6 s = 80 s**; warm refresh 3–5 s; 169 of 169 files, 0 failed, no missing thumbnails,
>   both times. Raw shell `afcclient` gets showed the difference is the device, not the app
>   ([`../../research.md`](../../research.md)). The slow run ended with a transient
>   `Invalid HostID (-21)` from the phone.
> - **Window (Step 3).** Seen in the real app launched via `open`: "Loading 143 of 163…" with a
>   progress bar, tiles filling in, a video tile with its glyph, Refresh and Download All disabled,
>   Cancel enabled; then "169 photos found" with Cancel gone. Captured with window-only
>   `screencapture -l` (a first full-screen capture grabbed personal content and was deleted).
> - **Steps 2 and 4 were replaced by XCUITests.** `sample` on the main thread and AppleScript
>   button clicks didn't pan out (SwiftUI buttons weren't reachable from AppleScript). Instead
>   `Tests/ip3gsUITests` (a page object, `MainWindow`, plus `LoadAndCancelUITests`) drives the real
>   app against the phone: it passed with a **genuinely cold cache** (72.7 s load; the app answered
>   accessibility queries throughout, thumbnails kept arriving, progress and Cancel appeared and
>   cleared) and Cancel + Refresh recovery (8.9 s). The first passing run was **not** cold — the
>   test deleted the cache under the runner's own home directory, not the app's — so the app now
>   honours `IP3GS_CACHE_DIR` and the tests point it at a temp directory.
> - **Not covered:** a Download All click in the real window (would overwrite the user's
>   `~/Pictures/ip3gs`), and a mutation check of the UI tests' freeze detection.

- [x] **Step 1: Scripted timing.** Extend `DeviceIntegrationTests`' full-library test (opt-in) to use
  the new `PhotoLibrary`: `await refresh()`, then `await downloadAll(to: tempDir)`, measuring
  each with `Date()`; assert 169 files land, 0 failed, and print both durations. Record them.

```bash
TEST_RUNNER_IP3GS_DEVICE=1 xcodebuild -project ip3gs.xcodeproj -scheme ip3gs \
  -destination 'platform=macOS' test -only-testing:ip3gsTests/DeviceIntegrationTests
```

  Target: refresh ~74 s (163 JPEGs) + download-all = the 6 `.MOV` pulls plus 163 local copies →
  total in the ~80 s range. The `.MOV` size is unknown, so treat ~80 s as the estimate and record
  the measured value; do not force it. If the run is more than ~30 % over, stop and report which
  of the two phases is over.
  Clear `~/Library/Caches/ip3gs` first (cold cache), then run a second time to record the
  warm-cache refresh (expected: seconds).

- ➜ **Step 2 (superseded by the XCUITests above): Responsiveness of the real app.** Launch as in Task 5 Step 4, then while the
  thumbnails are loading:

```bash
pid=$(pgrep -nx ip3gs); sample $pid 2 -file "$CLAUDE_JOB_DIR/tmp/sample.txt"
grep -c "waitUntilExit\|readDataToEndOfFile" "$CLAUDE_JOB_DIR/tmp/sample.txt"
```

  In the main-thread section of the sample the app should be idle in the run loop
  (`mach_msg`), not in `waitUntilExit`/`readDataToEndOfFile`. Those two calls may appear on a
  *background* thread; check which thread they are under.

- [x] **Step 3: Look at the window.** `screencapture -x "$CLAUDE_JOB_DIR/tmp/shot-N.png"` at ~5 s,
  ~30 s and when loading ends, and `Read` each PNG. Check: status text is legible and changes,
  progress bar advances, tiles fill in incrementally, video tiles show the glyph, the buttons are
  laid out sensibly, Cancel appears only while busy. If `screencapture` returns a blank/desktop
  image (Screen Recording not granted to the terminal host), report that and ask the user for
  one screenshot — do not claim the window was seen.

- ➜ **Step 4 (Cancel done by XCUITests; Download All click open): Cancel and Download All in the real window.** If Accessibility allows
  `osascript` to click buttons, do it; otherwise **ask the user** to click Cancel mid-load, then
  Refresh, then Download All, and report what they see. Verify afterwards:

```bash
ls ~/Pictures/ip3gs | wc -l        # 169
ls -a ~/Library/Caches/ip3gs/*/    # no .partial left behind
```

- [x] **Step 5: Record results** for Task 8. No commit here (no tracked changes).

Back to the [milestone 2 plan](README.md).
