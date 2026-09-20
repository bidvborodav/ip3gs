# Milestone 2 — usable POC: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development`
> (recommended) or `superpowers:executing-plans`. Steps use checkbox (`- [ ]`) syntax.
> **TDD is off for this POC** ([`../best-practices.md`](../best-practices.md#tdd-is-disabled-for-the-poc)):
> write the code, then the test, then run, then commit. Do not run red-green cycles.

**Goal:** the app launches from Finder and stays responsive with the phone attached.

**Branch:** `poc/milestone-2-usable` (from `worktree-poc-milestone-1`, which holds all
milestone-1 code and is not merged to `main`).

**Architecture:** `DeviceBridge` stays synchronous and blocking (it is the process seam).
`PhotoLibrary` becomes `@MainActor` and runs each blocking bridge call on a background
thread, publishing after every file. A new `PhotoCache` pulls each full-size file once into
`~/Library/Caches/ip3gs/<udid>/`; thumbnails are made from it and "Download All" copies from
it. `Tools/bin` binaries are copied into `ip3gs.app/Contents/MacOS` at build time and resolved
with `Bundle.main.url(forAuxiliaryExecutable:)`.

**Tech stack:** Swift / SwiftUI, Swift concurrency, ImageIO, xcodegen `copyFiles`, XCTest.

This milestone is roughly Phase 0–1 of the native sync app, as the smallest slice.
Milestone 3 (Phase 0 spikes, chiefly one `afcclient` session doing many `get`s vs one spawn per
file) is **out of scope** — but it would change the per-file shape of `DeviceBridging.download`,
so this plan keeps that method exactly as it is.

## Done when

- [ ] Launched from Finder (`open`, cwd `/`) with the phone attached, the window never freezes.
- [ ] Thumbnails appear incrementally while the grid is still loading.
- [ ] All 169 files reach `~/Pictures/ip3gs/`; refresh + download total in the ~80 s range.
- [ ] Cancel stops cleanly (no crash, no half-written files, status says how far it got).
- [ ] Both bundled binaries link only system libraries.
- [ ] The window was launched and looked at (grid, status text, buttons).
- [ ] Untrusted path tried, or recorded as unreachable on this device (needs the user).

## Judgement calls made (change any of these before executing)

| Call | Why |
|---|---|
| Cache in `~/Library/Caches/ip3gs/<udid>/`, not `~/Pictures/ip3gs/` | Browsing must not write into the user's Pictures folder; the OS may reclaim caches, which is safe because the cache is re-fillable. |
| Cache key is `udid` + filename, no size/mtime check | `ls` returns bare names only. **[assumed]** iOS never reuses `IMG_nnnn` for different content on one device. Recorded in `research.md`. |
| Cache fills via a temp `.partial` dir, then `moveItem` | A kill mid-`get` must never leave a truncated file that later counts as a cache hit. |
| Cancel is checked **between files** | Worst-case latency is one file (~0.5 s). Killing `afcclient` mid-transfer is more code for no user-visible gain. |
| Thumbnails are downsampled to 200 px (Task 4) | Otherwise 163 full 2048x1536 JPEGs (~160 MB) sit in memory and each grid redraw re-decodes them — the kind of jank this milestone exists to remove. Drop Task 4 if Task 6 shows the window is fine without it. |
| Add a **Refresh** button | Without it, Cancel during the first load is a dead end and a re-plugged phone needs an app relaunch. |
| Progress = status string **plus** a `ProgressView` bar | Keeps the "one status-bar string" rule; the bar is the standard determinate-progress control (Apple HIG). |
| `downloadThumbnail` is deleted, not kept | The cache makes it dead code (YAGNI). Its tests are replaced, not ported. |

## File structure

| File | Change | Responsibility |
|---|---|---|
| `Sources/ip3gs/DeviceBridge/PhotoAsset.swift` | modify | add `isVideo` |
| `Sources/ip3gs/PhotoCache.swift` | **create** | per-device on-disk cache: fill once, copy out |
| `Sources/ip3gs/Thumbnail.swift` | **create** | file → 200 px JPEG `Data` (Task 4) |
| `Sources/ip3gs/PhotoLibrary.swift` | modify | async, cancellable, progress; uses cache; skips video thumbnails |
| `Sources/ip3gs/ContentView.swift` | modify | progress bar, Cancel, Refresh, video glyph |
| `Sources/ip3gs/DeviceBridge/DeviceBridge.swift` | modify | bundle-relative `binDir` default; delete `downloadThumbnail` |
| `project.yml` | modify | `copyFiles` the two binaries into the app |
| `Tests/ip3gsTests/*` | modify/create | see each task |

---

## Task 0: Worktree baseline

**Files:** none tracked.

- [ ] **Step 1: Give the worktree its binaries.** `Tools/bin/` is gitignored, so a fresh
  worktree has none. Copy from the main checkout (built by `Tools/setup.sh`):

```bash
cp -R /Users/dr.reddys/Documents/GitHub/ip3gs/Tools/bin Tools/bin
otool -L Tools/bin/afcclient Tools/bin/ideviceinfo   # system libraries only
```

- [ ] **Step 2: Generate the project and run the baseline.**

```bash
xcodegen generate
xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test
```

Expected: `** TEST SUCCEEDED **`, 23 tests, the 5 `DeviceIntegrationTests` skipped.

- [ ] **Step 3: Note the Swift language mode.** `xcodebuild -showBuildSettings | grep SWIFT_VERSION`.
  If it is 6, the `Sendable` annotations in Task 3b are errors, not warnings — fix them, do not
  silence them.

---

## Task 1: `PhotoAsset.isVideo`

**Files:** modify `Sources/ip3gs/DeviceBridge/PhotoAsset.swift`; test in a new
`Tests/ip3gsTests/PhotoAssetTests.swift`.

- [ ] **Step 1: Implement.** One definition, used by the library (skip thumbnails) and the view
  (glyph):

```swift
struct PhotoAsset: Identifiable, Equatable {
    let id: String
    let filename: String
    let remotePath: String

    var isVideo: Bool { filename.lowercased().hasSuffix(".mov") }
}
```

- [ ] **Step 2: Test.**

```swift
import XCTest
@testable import ip3gs

final class PhotoAssetTests: XCTestCase {
    private func asset(_ name: String) -> PhotoAsset {
        PhotoAsset(id: name, filename: name, remotePath: "/DCIM/100APPLE/\(name)")
    }

    func testMovIsVideoRegardlessOfCase() {
        XCTAssertTrue(asset("IMG_0001.MOV").isVideo)
        XCTAssertTrue(asset("img_0001.mov").isVideo)
    }

    func testJpegIsNotVideo() {
        XCTAssertFalse(asset("IMG_0001.JPG").isVideo)
    }
}
```

- [ ] **Step 3: Run** `... test -only-testing:ip3gsTests/PhotoAssetTests` → passes.
- [ ] **Step 4: Commit** `feat: flag video assets` (stage the two files only).

---

## Task 2: `PhotoCache` (new file, no behaviour change yet)

**Files:** create `Sources/ip3gs/PhotoCache.swift`, `Tests/ip3gsTests/PhotoCacheTests.swift`.

The cache takes the bridge only for the miss path, so it is testable with a fake bridge and a
temp directory.

- [ ] **Step 1: Implement.**

```swift
import Foundation

/// On-disk copy of full-size downloads for one device. Pull once, reuse for thumbnails and
/// "Download All". Cache key is the filename — see research.md #8 for the staleness assumption.
struct PhotoCache: Sendable {
    let directory: URL

    func file(for asset: PhotoAsset) -> URL {
        directory.appendingPathComponent(asset.filename)
    }

    func contains(_ asset: PhotoAsset) -> Bool {
        FileManager.default.fileExists(atPath: file(for: asset).path)
    }

    /// Returns the cached file, pulling it from the device on a miss. nil if the pull fails.
    /// The pull lands in `.partial` first so an interrupted `get` is never mistaken for a hit.
    func fill(_ asset: PhotoAsset, using bridge: DeviceBridging) -> URL? {
        if contains(asset) { return file(for: asset) }
        let partial = directory.appendingPathComponent(".partial")
        let fm = FileManager.default
        try? fm.removeItem(at: partial)
        guard (try? fm.createDirectory(at: partial, withIntermediateDirectories: true)) != nil,
              bridge.download(asset, to: partial),
              (try? fm.moveItem(at: partial.appendingPathComponent(asset.filename), to: file(for: asset))) != nil
        else { return nil }
        return file(for: asset)
    }

    /// Copies a cached file into `destination`, replacing any file already there. False on a miss.
    func copy(_ asset: PhotoAsset, to destination: URL) -> Bool {
        guard contains(asset) else { return false }
        let target = destination.appendingPathComponent(asset.filename)
        let fm = FileManager.default
        try? fm.removeItem(at: target)
        return (try? fm.copyItem(at: file(for: asset), to: target)) != nil
    }
}
```

- [ ] **Step 2: Tests** (temp dir per test, a small fake `DeviceBridging` that writes bytes into the
  `directory` it is handed and counts calls). Cover:
  1. `fill` on a miss calls `bridge.download` once and returns a file with the fake's bytes.
  2. `fill` on a hit does **not** call the bridge.
  3. `fill` when `bridge.download` returns false returns nil and leaves no file in the cache.
  4. A stale `.partial/IMG.JPG` from an earlier interrupted run is not treated as a hit and
     is replaced.
  5. `copy` on a hit writes the file to the destination (also over an existing file); `copy` on a
     miss returns false.

  `DeviceBridging` still has `downloadThumbnail` at this point — the fake must implement it
  (Task 3a deletes it).

- [ ] **Step 3: Run** `-only-testing:ip3gsTests/PhotoCacheTests` → passes.
- [ ] **Step 4: Commit** `feat: add per-device photo cache`.

---

## Task 3a: `PhotoLibrary` uses the cache and skips video thumbnails (still synchronous)

**Files:** modify `PhotoLibrary.swift`, `DeviceBridge.swift`, `PhotoLibraryTests.swift`,
`DeviceBridgeDownloadTests.swift`, `DeviceIntegrationTests.swift`.

Small, green step first; async comes after.

- [ ] **Step 1: Delete `downloadThumbnail`** from the `DeviceBridging` protocol and from
  `DeviceBridge.swift` (lines ~65–78, the whole method plus its comment). Delete its tests in
  `DeviceBridgeDownloadTests.swift` (the ones whose names/bodies call `downloadThumbnail`) and
  rewrite the two `DeviceIntegrationTests` assertions (lines ~51 and ~81) to call
  `bridge.download(_:to:)` into a temp dir and check the JPEG SOI bytes (`FF D8`) / the failure.

- [ ] **Step 2: `PhotoLibrary` takes a cache root and stores the current device's cache.**

```swift
private let cacheRoot: URL
private var cache: PhotoCache?

init(bridge: DeviceBridging,
     cacheRoot: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
         .appendingPathComponent("ip3gs")) {
    self.bridge = bridge
    self.cacheRoot = cacheRoot
}
```

- [ ] **Step 3: `refresh()` connected branch** — cache each non-video asset, read it back:

```swift
case .connected(let udid):
    let cache = PhotoCache(directory: cacheRoot.appendingPathComponent(udid))
    self.cache = cache
    assets = bridge.listPhotos(udid: udid)
    for asset in assets where !asset.isVideo {
        if let file = cache.fill(asset, using: bridge) {
            thumbnails[asset.filename] = try? Data(contentsOf: file)
        }
    }
    statusText = "\(assets.count) photo\(assets.count == 1 ? "" : "s") found"
```

  `.notConnected` / `.untrusted` also set `cache = nil`.

- [ ] **Step 4: `downloadAll`** — copy from cache, else pull straight to the destination:

```swift
if cache?.copy(asset, to: directory) == true || bridge.download(asset, to: directory) {
    succeeded += 1
} else {
    failedDownloads.append(asset.filename)
}
```

- [ ] **Step 5: Update `PhotoLibraryTests`.** `FakeBridge` gets a `downloadCount` per filename and
  writes a byte into the directory it is handed (so cache hits are real). Add, with a temp
  `cacheRoot` per test:
  1. a `.MOV` in the listing is **not** pulled during `refresh()` and has no thumbnail;
  2. `downloadAll` after `refresh()` pulls each JPEG **once in total** (count == 1) and the files
     exist in the destination;
  3. `downloadAll` still pulls the `.MOV` (it is not cached) — count == 1;
  4. existing failure test still passes (a failing pull is listed and non-fatal).

- [ ] **Step 6: Run the full unit suite** → `** TEST SUCCEEDED **`.
- [ ] **Step 7: Commit** `refactor: pull each photo once via cache, skip video thumbnails`.

---

## Task 3b: async, cancellable, with progress

**Files:** modify `PhotoLibrary.swift`, `ContentView.swift`, `ip3gsApp.swift` (only if the
`@StateObject` init needs `@MainActor` help), `PhotoLibraryTests.swift`.

- [ ] **Step 1: Make the seams `Sendable`.** `protocol DeviceBridging: Sendable`,
  `protocol ProcessRunning: Sendable`. `DeviceBridge` is a final class of `let`s, so it conforms
  as-is once `ProcessRunning` is `Sendable`. Test doubles that hold mutable state are
  `@unchecked Sendable` (they are only touched serially).

- [ ] **Step 2: Rewrite the `PhotoLibrary` class.** Work methods are `async` and cancellable via
  the surrounding `Task`; thin `start…` wrappers own the `Task` so views never touch concurrency.

```swift
@MainActor
final class PhotoLibrary: ObservableObject {
    @Published private(set) var statusText = "No device connected"
    @Published private(set) var assets: [PhotoAsset] = []
    @Published private(set) var thumbnails: [String: Data] = [:]
    @Published private(set) var failedDownloads: [String] = []
    /// 0...1 while a refresh or download runs; nil when idle. `isBusy` derives from it.
    @Published private(set) var progress: Double?

    var isBusy: Bool { progress != nil }

    private let bridge: DeviceBridging
    private let cacheRoot: URL
    private var cache: PhotoCache?
    private var task: Task<Void, Never>?

    // init as in Task 3a

    func startRefresh() { run { await $0.refresh() } }
    func startDownloadAll(to directory: URL) { run { await $0.downloadAll(to: directory) } }
    func cancel() { task?.cancel() }

    private func run(_ work: @escaping @MainActor (PhotoLibrary) async -> Void) {
        guard task == nil else { return }
        progress = 0
        task = Task {
            await work(self)
            progress = nil
            task = nil
        }
    }

    /// Runs a blocking bridge call off the main thread. One at a time by construction: callers
    /// await each result before starting the next, so the USB device is never hit concurrently.
    private func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated, operation: work).value
    }

    func refresh() async {
        let bridge = self.bridge
        switch await offMain({ bridge.checkConnection() }) {
        case .notConnected:
            cache = nil; assets = []; thumbnails = [:]
            statusText = "No device connected"
        case .untrusted:
            cache = nil; assets = []; thumbnails = [:]
            statusText = "Trust this computer on the iPhone"
        case .connected(let udid):
            let cache = PhotoCache(directory: cacheRoot.appendingPathComponent(udid))
            self.cache = cache
            thumbnails = [:]
            assets = await offMain { bridge.listPhotos(udid: udid) }
            let pending = assets.filter { !$0.isVideo }
            for (index, asset) in pending.enumerated() {
                if Task.isCancelled {
                    statusText = "Cancelled — \(index) of \(pending.count) thumbnails loaded"
                    return
                }
                progress = Double(index) / Double(pending.count)
                statusText = "Loading \(index + 1) of \(pending.count)…"
                thumbnails[asset.filename] = await offMain {
                    cache.fill(asset, using: bridge).flatMap { try? Data(contentsOf: $0) }
                }
            }
            statusText = "\(assets.count) photo\(assets.count == 1 ? "" : "s") found"
        }
    }

    func downloadAll(to directory: URL) async {
        let bridge = self.bridge, cache = self.cache
        failedDownloads = []
        var succeeded = 0
        for (index, asset) in assets.enumerated() {
            if Task.isCancelled {
                statusText = "Cancelled — downloaded \(succeeded) of \(assets.count)"
                return
            }
            progress = Double(index) / Double(assets.count)
            statusText = "Downloading \(index + 1) of \(assets.count)…"
            let ok = await offMain {
                cache?.copy(asset, to: directory) == true || bridge.download(asset, to: directory)
            }
            if ok { succeeded += 1 } else { failedDownloads.append(asset.filename) }
        }
        statusText = failedDownloads.isEmpty
            ? "Downloaded \(succeeded) of \(assets.count)"
            : "Downloaded \(succeeded) of \(assets.count) (\(failedDownloads.count) failed)"
    }
}
```

  Note `thumbnails[...] = nil` for a failed pull is a no-op assignment of `nil` — fine, the tile
  stays a placeholder.

- [ ] **Step 3: `ContentView`.**
  - Under the status text: `if let progress = library.progress { ProgressView(value: progress) }`
    with 8 pt horizontal padding.
  - Bottom bar becomes an `HStack`: **Refresh** (`library.startRefresh()`), **Download All**
    (`library.startDownloadAll(to: destination)`), both `.disabled(library.isBusy)`
    (Download All also `.disabled(library.assets.isEmpty)`); and, only `if library.isBusy`,
    **Cancel** (`library.cancel()`, `.keyboardShortcut(.cancelAction)` so Esc works).
  - `.onAppear { library.startRefresh() }`.
  - Placeholder tile: for `asset.isVideo` overlay `Image(systemName: "video")` in `.secondary`;
    give it `.accessibilityLabel("Video")`.

- [ ] **Step 4: Tests** (`@MainActor final class PhotoLibraryTests`, `async` test methods; call
  `await library.refresh()` directly — the `start…` wrappers stay thin and untested).
  1. Existing behaviour tests converted to `await`.
  2. **Responsiveness:** fake bridge whose `download` does `Thread.sleep(forTimeInterval: 0.05)`
     for 20 assets. Start `let refresh = Task { await library.refresh() }` and, meanwhile,
     `for _ in 0..<10 { try await Task.sleep(nanoseconds: 20_000_000); ticks += 1 }` on the main
     actor. Assert `ticks == 10` **and** the refresh has not finished when the ticks are done —
     proof the main actor was free while the bridge blocked. (Before this task the same shape
     would hang the main actor for the full duration.)
  3. **Incremental:** in the same ticking loop as (2), record `library.thumbnails.count` at each
     tick and assert that at some tick it is strictly between 0 and 20 — thumbnails were published
     while the refresh was still running, not all at the end.
  4. **Cancel (refresh):** drive through `startRefresh()`. The fake bridge's `download` sets a flag
     after its 3rd call; the test polls that flag from the main actor (20 ms sleeps), calls
     `library.cancel()`, then waits until `library.isBusy == false`. Assert `statusText` starts with
     `"Cancelled — "`, fewer than 20 thumbnails exist (at most one more than the flag point, since
     the in-flight file is allowed to finish), and `isBusy == false`.
  5. **Cancel (download):** same shape via `startDownloadAll`; assert `statusText` starts with
     `"Cancelled — downloaded "`, the destination holds fewer files than the asset count, and no
     `.partial` directory is left in the cache.
  6. `startRefresh()` while busy is a no-op (bridge `checkConnection` called once).

- [ ] **Step 5: Run the full unit suite** → `** TEST SUCCEEDED **`, then
  `xcodebuild ... build` for the app target.
- [ ] **Step 6: Commit** `feat: run refresh and download off the main thread with progress and cancel`.

---

## Task 4: Downsampled thumbnails (optional — see judgement calls)

**Files:** create `Sources/ip3gs/Thumbnail.swift`, `Tests/ip3gsTests/ThumbnailTests.swift`;
modify `PhotoLibrary.swift` (one line) and `PhotoLibraryTests.swift` (fixture bytes).

- [ ] **Step 1: Implement.**

```swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum Thumbnail {
    /// JPEG data for a grid tile: longest side `maxPixel`, EXIF orientation applied.
    /// 200 px = a 100 pt tile at 2x. nil if the file is not a decodable image.
    static func data(from file: URL, maxPixel: Int = 200) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        let output = NSMutableData()
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
```

- [ ] **Step 2: Use it** in `PhotoLibrary.refresh()`: replace `try? Data(contentsOf: $0)` with
  `Thumbnail.data(from: $0)`. The fake bridge in `PhotoLibraryTests` must now write a real JPEG
  (generate a 400x300 one with `NSBitmapImageRep`/`CGContext` in a test helper) instead of
  `Data([0x01])`.

- [ ] **Step 3: Test.** Generate a 1000x500 JPEG into a temp file; `Thumbnail.data(from:)` returns
  data that decodes (`CGImageSourceCreateWithData`) to an image whose longer side is `<= 200` and
  whose aspect ratio is ~2:1; a text file returns nil.
- [ ] **Step 4: Run the full unit suite**, then commit `feat: downsample grid thumbnails to 200 px`.

---

## Task 5: Bundle the binaries

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

---

## Task 6: Verify on the real device and look at the window

Hardware is attached now (`ideviceinfo` reports iOS 6.1.6). No code unless a check fails.

- [ ] **Step 1: Scripted timing.** Extend `DeviceIntegrationTests`' full-library test (opt-in) to use
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

- [ ] **Step 2: Responsiveness of the real app.** Launch as in Task 5 Step 4, then while the
  thumbnails are loading:

```bash
pid=$(pgrep -nx ip3gs); sample $pid 2 -file "$CLAUDE_JOB_DIR/tmp/sample.txt"
grep -c "waitUntilExit\|readDataToEndOfFile" "$CLAUDE_JOB_DIR/tmp/sample.txt"
```

  In the main-thread section of the sample the app should be idle in the run loop
  (`mach_msg`), not in `waitUntilExit`/`readDataToEndOfFile`. Those two calls may appear on a
  *background* thread; check which thread they are under.

- [ ] **Step 3: Look at the window.** `screencapture -x "$CLAUDE_JOB_DIR/tmp/shot-N.png"` at ~5 s,
  ~30 s and when loading ends, and `Read` each PNG. Check: status text is legible and changes,
  progress bar advances, tiles fill in incrementally, video tiles show the glyph, the buttons are
  laid out sensibly, Cancel appears only while busy. If `screencapture` returns a blank/desktop
  image (Screen Recording not granted to the terminal host), report that and ask the user for
  one screenshot — do not claim the window was seen.

- [ ] **Step 4: Cancel and Download All in the real window.** If Accessibility allows
  `osascript` to click buttons, do it; otherwise **ask the user** to click Cancel mid-load, then
  Refresh, then Download All, and report what they see. Verify afterwards:

```bash
ls ~/Pictures/ip3gs | wc -l        # 169
ls -a ~/Library/Caches/ip3gs/*/    # no .partial left behind
```

- [ ] **Step 5: Record results** for Task 8. No commit here (no tracked changes).

---

## Task 7: Untrusted path — **needs the user**

The code's assumed lockdown codes (`-17/-18/-19/-21`) stay unconfirmed until a real untrusted
phone reports one.

- [ ] **Step 1 (user): make this Mac unknown to the phone.** Either use a phone that has never
  paired with this Mac, or reset this one: on the phone, Settings → General → Reset → *Reset
  Location & Privacy* (label from memory for iOS 6 — **[assumed]**), and on the Mac remove the
  stored pairing record: `sudo rm /var/db/lockdown/<UDID>.plist` (UDID from
  `Tools/bin/ideviceinfo` or the list above).
- [ ] **Step 2: Capture.** Unplug, replug, then run `Tools/bin/ideviceinfo; echo "exit=$?"` and
  paste stderr/exit code into the session. Then launch the app and note the status text.
- [ ] **Step 3: Record the outcome either way.**
  - If a code in the assumed set appears → mark it **verified** in `domain.md` and `research.md`,
    and make the unit-test fixture match the captured stderr byte-for-byte.
  - If another code appears → add it to `untrustedLockdownCodes` and fix the fixture.
  - If the phone **pairs silently with no prompt** → that is the answer: **[assumed, from memory]**
    the "Trust This Computer" dialog arrived in iOS 7, so an iOS 6.1.6 3GS may never present an
    untrusted state. Record it in `domain.md`; keep the trust-code branch (other devices) but
    mark it untestable on this hardware.

---

## Task 8: Docs (after Tasks 1–6 pass)

**Files:** `docs/experiments/README.md`, `docs/domain.md`, `docs/research.md`,
`docs/architecture.md`, root `CLAUDE.md`. Keep root `CLAUDE.md` under 150 lines.

- [ ] `docs/experiments/README.md`: status table gets a milestone-2 block; replace **Next step**
  with milestone 3 (Phase 0 spikes); link this plan.
- [ ] `docs/architecture.md`: `PhotoLibrary` is `@MainActor`, async, one bridge call at a time;
  add `PhotoCache`; binary resolution now = `Bundle.main.url(forAuxiliaryExecutable:)` with the
  build-time `copyFiles`; delete `downloadThumbnail` from the surface listing; refresh the
  "Build state" banner.
- [ ] `docs/domain.md`: video handling (listed and downloaded, never thumbnailed), the cache
  location, the untrusted-path outcome from Task 7.
- [ ] `docs/research.md`: mark #7 settled; add **#8** — cache key is `udid`+filename with no
  staleness check (**[assumed]** names are never reused for different content); record the
  measured timings from Task 6.
- [ ] Root `CLAUDE.md`: current state; `Tools/bin/` must be populated (`./Tools/setup.sh`) **before**
  `xcodebuild` because the build copies it into the app; drop the stale "Prerequisites (unmet)"
  block if all three are now met (they are: the milestone-1 build and tests ran).
- [ ] Commit `docs: record milestone 2 results`.

---

## Self-review against the scope

| Scope item | Covered by |
|---|---|
| 1. Unblock the UI, incremental thumbnails, progress, cancel | Task 3b (+ Task 4 to keep redraws cheap; Task 6 proves it) |
| 2. Pull each photo once | Tasks 2, 3a |
| 3. Bundle the binaries | Task 5 |
| 4. Skip videos for thumbnails | Tasks 1, 3a (download unchanged) |
| 5. Look at the window | Task 6 |
| 6. Untrusted path | Task 7 (needs the user) |

**Known risks, in order of likelihood:**
1. `codeSign: true` on copied helpers or hardened runtime rejects the helpers → Task 5 Step 3/4
   catches it before any hardware time is spent.
2. `screencapture` / `osascript` blocked by macOS privacy permissions in this session →
   Task 6 falls back to asking the user, and says so.
3. Swift 6 mode turns the `Sendable` warnings into errors → Task 0 Step 3 finds out first.
4. The ~80 s estimate is off because `.MOV` pulls are large → measured and reported, not forced.
