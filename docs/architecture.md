# Architecture

> **Build state (2026-09-20):** all three layers are implemented and pass
> their tests against fakes; nothing has been run against a real device. See
> [`experiments/README.md`](experiments/README.md) for status.

Three layers, each independently testable, deliberately thin. This is a POC:
correctness and honest failure states matter more than polish.

```
SwiftUI views  ──reads──▶  PhotoLibrary  ──DeviceBridging──▶  DeviceBridge
  (stateless)             (state + rules)                    (device I/O)
                                                                   │
                                                          ProcessRunning
                                                                   │
                                                    Tools/bin/{ideviceinfo,afcclient}
```

## 1. `DeviceBridge` — `Sources/ip3gs/DeviceBridge/`

The only code that touches the device. Shells out via `Process` to the
vendored CLI binaries. No C interop, no `$PATH` lookup, no system install.

All process execution goes through an injectable seam:

```swift
protocol ProcessRunning {
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
struct PhotoAsset: Identifiable, Equatable { let id, filename, remotePath: String }

func checkConnection() -> DeviceState
func listPhotos(udid: String) -> [PhotoAsset]
func downloadThumbnail(_ asset: PhotoAsset) -> Data?
func download(_ asset: PhotoAsset, to directory: URL) -> Bool
```

Nothing here throws. Failures return `nil`/`false`/`.notConnected` and the
caller decides how to surface them — errors are UI state in this app, not
exceptions.

**Editing constraint:** `binDir` and `runner` are `private`. New methods go
**inside** the existing `final class DeviceBridge { ... }` body. A separate
`extension` cannot reach them and will not compile. This has already bitten
once (see the pre-flight ruling in
[`experiments/README.md`](experiments/README.md)).

## 2. `PhotoLibrary` — `Sources/ip3gs/PhotoLibrary.swift`

`ObservableObject` owning `[PhotoAsset]`, thumbnails, and download state. The
sole consumer of `DeviceBridge`, reached through a `DeviceBridging` protocol
so tests inject a fake rather than a real bridge.

This is where the business rules live:

- Not connected → `"No device connected"`, assets cleared.
- Untrusted → `"Trust this computer on the iPhone"`, assets cleared.
- Connected → list, then fetch a thumbnail per asset, then report the count.
- **A per-file download failure is non-fatal.** It is collected into
  `failedDownloads` and the batch continues. One bad photo must never abort
  the other 400.

## 3. SwiftUI views — `Sources/ip3gs/`

One window: status bar, `LazyVGrid` thumbnail grid, one "Download All"
button. A stateless read of `PhotoLibrary` with no business logic of its own.

## Binary resolution and portability

`DeviceBridge` locates `ideviceinfo` and `afcclient` **by path relative to the
app's resource bundle** (or `Tools/bin/` in dev builds) — never `$PATH`.

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
