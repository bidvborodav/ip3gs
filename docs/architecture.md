# Architecture

> **Build state (2026-09-20, milestone 2):** all layers are implemented, tested
> against fakes, and verified against a real iPhone 3GS (integration tests and
> XCUITests). See [`experiments/README.md`](experiments/README.md) for status.

Three layers, each independently testable, deliberately thin. This is a POC:
correctness and honest failure states matter more than polish.

```
SwiftUI views  ──reads──▶  PhotoLibrary  ──DeviceBridging──▶  DeviceBridge
  (stateless)             (state + rules)                    (device I/O)
                           │        │                               │
                  PhotoCache   Thumbnail                   ProcessRunning
                 (disk cache)  (200 px JPEG)                        │
                                                   ip3gs.app/Contents/MacOS/{ideviceinfo,afcclient}
```

## 1. `DeviceBridge` — `Sources/ip3gs/DeviceBridge/`

The only code that touches the device. Shells out via `Process` to the
vendored CLI binaries. No C interop, no `$PATH` lookup, no system install.

All process execution goes through an injectable seam:

```swift
protocol ProcessRunning: Sendable {
    func run(_ executablePath: String, arguments: [String], stdin: String?)
        throws -> (stdout: Data, stderr: String, exitCode: Int32)
}
```

`stdout` is `Data` because photo bytes are not UTF-8; `stdin` exists because
`afcclient` takes its commands that way. `SystemProcessRunner` drains both
output pipes before waiting on the child, or output past the 64 KB pipe buffer
deadlocks it.

`SystemProcessRunner` is the real implementation; tests inject a fake. That
seam is the whole reason the parsing logic is unit-testable with no phone
plugged in — it is the most load-bearing design decision in the project.

Surface:

```swift
enum DeviceState: Equatable { case notConnected, untrusted, connected(udid: String) }
struct PhotoAsset: Identifiable, Equatable { let id, filename, remotePath: String; var isVideo: Bool }

func checkConnection() -> DeviceState
func listPhotos(udid: String) -> [PhotoAsset]
func download(_ asset: PhotoAsset, to directory: URL) -> Bool
```

There is no thumbnail method: the device has no cheap per-photo thumbnail, so a
thumbnail is a full `download` into the cache (see `PhotoCache`) downsampled by
`Thumbnail`. `DeviceBridge` is `Sendable` and is called from background threads.

Nothing here throws. Failures return `nil`/`false`/`.notConnected` and the
caller decides how to surface them — errors are UI state in this app, not
exceptions.

**Editing constraint:** `binDir` and `runner` are `private`. New methods go
**inside** the existing `final class DeviceBridge { ... }` body. A separate
`extension` cannot reach them and will not compile. This has already bitten
once (see the pre-flight ruling in
[`experiments/README.md`](experiments/README.md)).

## 2. `PhotoLibrary` — `Sources/ip3gs/PhotoLibrary.swift`

`@MainActor ObservableObject` owning `[PhotoAsset]`, thumbnails, progress, and
download state. The sole consumer of `DeviceBridge`, reached through a
`Sendable` `DeviceBridging` protocol so tests inject a fake rather than a real
bridge.

**Concurrency rule.** `refresh()` and `downloadAll(to:)` are `async`. Every
blocking bridge call goes through `offMain` (a detached task) and is awaited
before the next starts, so the main actor is never blocked and the USB device is
never hit by two calls at once. State is published after every file, which is
what makes thumbnails appear incrementally. `startRefresh()` /
`startDownloadAll(to:)` own the `Task` (ignored while one is running);
`cancel()` cancels it. Cancellation is checked **between files**, so worst-case
latency is one file (~0.5 s) and no half-written file is left behind.

Business rules:

- Not connected → `"No device connected"`, assets cleared.
- Untrusted → `"Trust this computer on the iPhone"`, assets cleared.
- Connected → list, then cache and downsample a thumbnail per **non-video**
  asset (`Loading n of m…`), then `"N photos found"`.
- Download All copies each file from the cache, or pulls it straight to the
  destination if it was never cached (videos). `Downloading n of m…`.
- Cancelled → `"Cancelled — <how far it got>"`; the listing survives.
- **A per-file download failure is non-fatal.** It is collected into
  `failedDownloads` and the batch continues. One bad photo must never abort
  the other 400.

### `PhotoCache` — `Sources/ip3gs/PhotoCache.swift`

Per-device directory `~/Library/Caches/ip3gs/<udid>/` of full-size downloads:
`fill` pulls once (via a `.partial` directory, so an interrupted pull is never a
hit), `copy` copies out. Keyed by filename with no staleness check —
**[assumed]** names are not reused for different content
([`research.md`](research.md)). The root is overridable for tests
(`PhotoLibrary(cacheRoot:)`, and `IP3GS_CACHE_DIR` in the app for UI tests).

### `Thumbnail` — `Sources/ip3gs/Thumbnail.swift`

ImageIO downsample of a cached file to 200 px (a 100 pt tile at 2x), so the
grid holds small 200 px JPEGs instead of ~1 MB originals and never re-decodes
full-size images while redrawing. (Memory and scroll smoothness were not
measured; this removes the known cost, it is not benchmarked.)

## 3. SwiftUI views — `Sources/ip3gs/`

One window: status bar with a determinate progress bar while busy, `LazyVGrid`
thumbnail grid (videos show a placeholder with a video glyph), and Refresh /
Download All / Cancel buttons (Cancel only while busy, Esc triggers it). A
stateless read of `PhotoLibrary` with no business logic of its own. Elements
carry accessibility identifiers (`status`, `progress`, `refresh`, `downloadAll`,
`cancel`, `thumbnail`) used by the UI tests' page object.

## Binary resolution and portability

`DeviceBridge` locates `ideviceinfo` and `afcclient` **inside the app bundle**
(`Bundle.main.url(forAuxiliaryExecutable:)`, i.e. `Contents/MacOS`) — never
`$PATH`. The build copies them there and re-signs them with the app
(`buildPhase: copyFiles` + `CodeSignOnCopy` on the `project.yml` source entries).
The `Tools/bin` fallback only applies when the bundle lookup fails.

This rule is what makes the shipped app portable, so it is worth stating what
it rules out: **do not** satisfy `Tools/bin/` by symlinking Homebrew's
`libimobiledevice`. Those binaries link against dylibs under `/opt/homebrew`
and break the moment the app leaves this machine. `Tools/setup.sh` builds from
source precisely so the output can be made self-contained.

Installing build-time dependencies on the dev machine is fine. The constraint
governs the *shipped tool*, not the developer's laptop.

## Deliberate non-features

Each of these is a cost avoided, not an omission:

| Choice | What it buys |
|---|---|
| Download path hardcoded to `~/Pictures/ip3gs/` | No folder picker, no sandbox entitlement work |
| No modals or alerts, ever | All state is one status-bar string; no alert-presentation plumbing |
| Shell out to CLI tools | No C interop build against libimobiledevice |
| `/DCIM/100APPLE` only | No roll-directory enumeration (see [`domain.md`](domain.md)) |
| No selection, delete, or metadata editing | Smallest complete loop that proves the path |
