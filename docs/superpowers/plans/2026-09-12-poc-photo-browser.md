# POC Photo Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect to a paired iPhone 3GS, list its photos, render thumbnails in a grid, and download all photos to a local folder — proving the device-communication path end to end with a minimal SwiftUI front end.

**Architecture:** `DeviceBridge` shells out to vendored `libimobiledevice` CLI binaries via an injectable `ProcessRunning` protocol (so business logic is unit-testable without a physical device). `PhotoLibrary` (an `ObservableObject`) owns app state and is the sole consumer of `DeviceBridge`. SwiftUI views are a thin, stateless read of `PhotoLibrary`.

**Tech Stack:** Swift 5.9+, SwiftUI, XCTest, vendored `libimobiledevice` (`ideviceinfo`, `afcclient`).

**Spec:** `docs/superpowers/specs/2026-09-12-poc-photo-browser-design.md`

## Global Constraints

- No global/Homebrew installs — all tooling lives under `Tools/` in this repo.
- Device library: `libimobiledevice`, invoked via `Process` (no C interop).
- Download destination: fixed `~/Pictures/ip3gs/` (no folder picker).
- Scope: list + thumbnail grid + "Download All" only — no selection, delete, or metadata editing.
- No modals/alerts — all state surfaces as plain text in a status bar.
- Platform: macOS 13+, SwiftUI, matching existing `project.yml`.

---

## Story Map (SPIDR / INVEST)

| # | Story | SPIDR axis | Why it's INVEST-sized |
|---|---|---|---|
| 1 | Vendor `libimobiledevice` binaries locally | **S**pike | Independent (no dependency on app code); resolves the riskiest unknown (can we get the binaries running at all, without global installs) before anything else is built |
| 2 | `DeviceBridge.checkConnection()` | **P**ath | Narrowest happy/known-error path through the device layer; testable via injected fake runner |
| 3 | `DeviceBridge.listPhotos()` | **I**nterface | New parsing interface (afcclient listing → `PhotoAsset`), independent of connection logic |
| 4 | `DeviceBridge.downloadThumbnail` / `download(to:)` | **D**ata | Same shape as Task 3 but a different data payload (binary file contents vs. text listing) and a different destination (memory vs. disk) |
| 5 | `PhotoLibrary` orchestration + error-state rules | **R**ules | Encodes the business rules (not-connected / untrusted / per-file-failure-is-non-fatal) on top of the mechanical layers 2–4 |
| 6 | SwiftUI views (status bar, grid, download button) | **P**ath | Happy-path UI wired to `PhotoLibrary`; no new business logic |
| 7 | Wire-up, manual device verification, docs | **R**ules | Closes the loop: real binaries + real device confirm the assumed CLI contract from Task 1 |

Each story is: **I**ndependent (own file(s), clear interface to neighbors), **N**egotiable (implementation detail free within the interface contract), **V**aluable (each produces a working, testable increment), **E**stimable (bounded to a few files), **S**mall (single sitting), **T**estable (unit tests except Task 7, which is manual by nature — no device in CI).

---

### Task 1: Vendor libimobiledevice binaries

**Files:**
- Create: `Tools/setup.sh`
- Modify: `.gitignore` (add `Tools/bin/`)
- Test: `Tools/setup_test.sh`

**Interfaces:**
- Produces: `Tools/bin/ideviceinfo`, `Tools/bin/afcclient` — executables on disk, consumed by `DeviceBridge` (Task 2) via a `binDir` parameter defaulting to `Tools/bin`.

- [ ] **Step 1: Write `Tools/setup.sh`**

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

- [ ] **Step 2: Add `Tools/bin/` to `.gitignore`**

Append to `.gitignore`:
```
Tools/bin/
```

- [ ] **Step 3: Write `Tools/setup_test.sh`** (verifies the script produces working binaries, without requiring a device)

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/setup.sh"

"$SCRIPT_DIR/bin/ideviceinfo" --version >/dev/null
"$SCRIPT_DIR/bin/afcclient" --version >/dev/null

echo "PASS: vendored binaries built and respond to --version"
```

- [ ] **Step 4: Run the test**

Run: `chmod +x Tools/setup.sh Tools/setup_test.sh && ./Tools/setup_test.sh`
Expected: `PASS: vendored binaries built and respond to --version`

> Note: this step requires build tooling (`autoconf`, `automake`, `libtool`, `pkg-config`) available on the Mac — these are developer-machine prerequisites, not app dependencies, and installing them is a one-time local decision for whoever runs setup, not a global runtime dependency of the app itself.

- [ ] **Step 5: Commit**

```bash
git add Tools/setup.sh Tools/setup_test.sh .gitignore
git commit -m "feat: add local libimobiledevice vendoring script"
```

---

### Task 2: `DeviceBridge.checkConnection()`

**Files:**
- Create: `Sources/ip3gs/DeviceBridge/ProcessRunning.swift`
- Create: `Sources/ip3gs/DeviceBridge/DeviceBridge.swift`
- Test: `Tests/ip3gsTests/DeviceBridgeConnectionTests.swift`

**Interfaces:**
- Produces:
  - `protocol ProcessRunning { func run(_ executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) }`
  - `struct SystemProcessRunner: ProcessRunning` — real `Process`-backed implementation
  - `enum DeviceState: Equatable { case notConnected; case untrusted; case connected(udid: String) }`
  - `final class DeviceBridge { init(binDir: String = "Tools/bin", runner: ProcessRunning = SystemProcessRunner()); func checkConnection() -> DeviceState }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ip3gs

private struct FakeRunner: ProcessRunning {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        (stdout, stderr, exitCode)
    }
}

final class DeviceBridgeConnectionTests: XCTestCase {
    func testNoDeviceConnected() {
        let runner = FakeRunner(stdout: "", stderr: "No device found.", exitCode: 1)
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)
        XCTAssertEqual(bridge.checkConnection(), .notConnected)
    }

    func testUntrustedDevice() {
        let runner = FakeRunner(stdout: "", stderr: "ERROR: Could not connect to lockdownd, error code -18", exitCode: 1)
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)
        XCTAssertEqual(bridge.checkConnection(), .untrusted)
    }

    func testConnectedDevice() {
        let stdout = "DeviceName: iPhone\nUniqueDeviceID: abc123\nProductVersion: 6.1.6\n"
        let runner = FakeRunner(stdout: stdout, stderr: "", exitCode: 0)
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)
        XCTAssertEqual(bridge.checkConnection(), .connected(udid: "abc123"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test -only-testing:ip3gsTests/DeviceBridgeConnectionTests`
Expected: FAIL — `ProcessRunning`, `DeviceBridge`, `DeviceState` do not exist yet.

- [ ] **Step 3: Write `ProcessRunning.swift`**

```swift
import Foundation

protocol ProcessRunning {
    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32)
}

struct SystemProcessRunner: ProcessRunning {
    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return (
            String(data: stdoutData, encoding: .utf8) ?? "",
            String(data: stderrData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }
}
```

- [ ] **Step 4: Write `DeviceBridge.swift`**

```swift
import Foundation

enum DeviceState: Equatable {
    case notConnected
    case untrusted
    case connected(udid: String)
}

final class DeviceBridge {
    private let binDir: String
    private let runner: ProcessRunning

    init(binDir: String = "Tools/bin", runner: ProcessRunning = SystemProcessRunner()) {
        self.binDir = binDir
        self.runner = runner
    }

    func checkConnection() -> DeviceState {
        guard let result = try? runner.run("\(binDir)/ideviceinfo", arguments: []) else {
            return .notConnected
        }

        if result.exitCode != 0 {
            if result.stderr.contains("error code -18") {
                return .untrusted
            }
            return .notConnected
        }

        for line in result.stdout.split(separator: "\n") {
            if line.hasPrefix("UniqueDeviceID:") {
                let udid = line.replacingOccurrences(of: "UniqueDeviceID:", with: "").trimmingCharacters(in: .whitespaces)
                return .connected(udid: udid)
            }
        }

        return .notConnected
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test -only-testing:ip3gsTests/DeviceBridgeConnectionTests`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add Sources/ip3gs/DeviceBridge/ProcessRunning.swift Sources/ip3gs/DeviceBridge/DeviceBridge.swift Tests/ip3gsTests/DeviceBridgeConnectionTests.swift
git commit -m "feat: add DeviceBridge connection check"
```

---

### Task 3: `DeviceBridge.listPhotos()`

**Files:**
- Create: `Sources/ip3gs/DeviceBridge/PhotoAsset.swift`
- Modify: `Sources/ip3gs/DeviceBridge/DeviceBridge.swift`
- Test: `Tests/ip3gsTests/DeviceBridgeListPhotosTests.swift`

**Interfaces:**
- Consumes: `DeviceBridge(binDir:runner:)`, `ProcessRunning` (Task 2)
- Produces:
  - `struct PhotoAsset: Identifiable, Equatable { let id: String; let filename: String; let remotePath: String }` (`id == filename`)
  - `extension DeviceBridge { func listPhotos(udid: String) -> [PhotoAsset] }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ip3gs

private struct FakeRunner: ProcessRunning {
    let stdout: String

    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        (stdout, "", 0)
    }
}

final class DeviceBridgeListPhotosTests: XCTestCase {
    func testParsesFilenameListIntoAssets() {
        let runner = FakeRunner(stdout: "IMG_0001.JPG\nIMG_0002.JPG\n")
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)

        let assets = bridge.listPhotos(udid: "abc123")

        XCTAssertEqual(assets, [
            PhotoAsset(id: "IMG_0001.JPG", filename: "IMG_0001.JPG", remotePath: "/DCIM/100APPLE/IMG_0001.JPG"),
            PhotoAsset(id: "IMG_0002.JPG", filename: "IMG_0002.JPG", remotePath: "/DCIM/100APPLE/IMG_0002.JPG"),
        ])
    }

    func testEmptyListingReturnsNoAssets() {
        let runner = FakeRunner(stdout: "")
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)

        XCTAssertEqual(bridge.listPhotos(udid: "abc123"), [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test -only-testing:ip3gsTests/DeviceBridgeListPhotosTests`
Expected: FAIL — `PhotoAsset` and `listPhotos` do not exist yet.

- [ ] **Step 3: Write `PhotoAsset.swift`**

```swift
struct PhotoAsset: Identifiable, Equatable {
    let id: String
    let filename: String
    let remotePath: String
}
```

- [ ] **Step 4: Add `listPhotos(udid:)` to `DeviceBridge.swift`**

```swift
extension DeviceBridge {
    private static let dcimPath = "/DCIM/100APPLE"

    func listPhotos(udid: String) -> [PhotoAsset] {
        guard let result = try? runner.run("\(binDir)/afcclient", arguments: ["-u", udid, "ls", Self.dcimPath]) else {
            return []
        }

        return result.stdout
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
            .map { filename in
                PhotoAsset(id: filename, filename: filename, remotePath: "\(Self.dcimPath)/\(filename)")
            }
    }
}
```

> Note: `binDir` and `runner` are `private` in Task 2 — change both to `private` → `fileprivate` (or keep `private` and put this extension in the same file) so this extension can reach them. Since this task modifies `DeviceBridge.swift` directly rather than adding a new file, just add the method inside the existing `final class DeviceBridge { ... }` body instead of a separate `extension`.

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test -only-testing:ip3gsTests/DeviceBridgeListPhotosTests`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit**

```bash
git add Sources/ip3gs/DeviceBridge/PhotoAsset.swift Sources/ip3gs/DeviceBridge/DeviceBridge.swift Tests/ip3gsTests/DeviceBridgeListPhotosTests.swift
git commit -m "feat: add DeviceBridge photo listing"
```

---

### Task 4: Thumbnail & download

**Files:**
- Modify: `Sources/ip3gs/DeviceBridge/DeviceBridge.swift`
- Test: `Tests/ip3gsTests/DeviceBridgeDownloadTests.swift`

**Interfaces:**
- Consumes: `PhotoAsset` (Task 3), `ProcessRunning` (Task 2)
- Produces:
  - `func downloadThumbnail(_ asset: PhotoAsset) -> Data?`
  - `func download(_ asset: PhotoAsset, to directory: URL) -> Bool` (returns success/failure, never throws — callers decide how to surface failure)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ip3gs

private struct FakeRunner: ProcessRunning {
    var stdoutData: String = "fake-image-bytes"
    var exitCode: Int32 = 0
    private(set) var lastArguments: [String] = []

    mutating func run(_ executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        lastArguments = arguments
        return (stdoutData, "", exitCode)
    }

    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        (stdoutData, "", exitCode)
    }
}

final class DeviceBridgeDownloadTests: XCTestCase {
    func testDownloadThumbnailReturnsData() {
        let runner = FakeRunner(stdoutData: "thumbnail-bytes", exitCode: 0)
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)
        let asset = PhotoAsset(id: "IMG_0001.JPG", filename: "IMG_0001.JPG", remotePath: "/DCIM/100APPLE/IMG_0001.JPG")

        let data = bridge.downloadThumbnail(asset)

        XCTAssertEqual(data, "thumbnail-bytes".data(using: .utf8))
    }

    func testDownloadThumbnailFailureReturnsNil() {
        let runner = FakeRunner(stdoutData: "", exitCode: 1)
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)
        let asset = PhotoAsset(id: "IMG_0001.JPG", filename: "IMG_0001.JPG", remotePath: "/DCIM/100APPLE/IMG_0001.JPG")

        XCTAssertNil(bridge.downloadThumbnail(asset))
    }

    func testDownloadWritesFileToDirectory() throws {
        let runner = FakeRunner(stdoutData: "full-image-bytes", exitCode: 0)
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)
        let asset = PhotoAsset(id: "IMG_0001.JPG", filename: "IMG_0001.JPG", remotePath: "/DCIM/100APPLE/IMG_0001.JPG")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let success = bridge.download(asset, to: tempDir)

        XCTAssertTrue(success)
        let written = try Data(contentsOf: tempDir.appendingPathComponent("IMG_0001.JPG"))
        XCTAssertEqual(written, "full-image-bytes".data(using: .utf8))
    }
}
```

> Note: drop the `mutating func run` / duplicate overload above — `ProcessRunning.run` is non-mutating in Task 2's protocol. Use only the single non-mutating `run` method shown for `testDownloadThumbnailReturnsData` etc.; `FakeRunner` here is a plain `struct` with `let stdoutData: String` and `let exitCode: Int32`, matching Task 2/3's fakes.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test -only-testing:ip3gsTests/DeviceBridgeDownloadTests`
Expected: FAIL — `downloadThumbnail` and `download(_:to:)` do not exist yet.

- [ ] **Step 3: Add `downloadThumbnail` and `download(to:)` to `DeviceBridge.swift`**

```swift
func downloadThumbnail(_ asset: PhotoAsset) -> Data? {
    guard let result = try? runner.run("\(binDir)/afcclient", arguments: ["-u", "", "get", asset.remotePath, "-"]),
          result.exitCode == 0 else {
        return nil
    }
    return result.stdout.data(using: .utf8)
}

func download(_ asset: PhotoAsset, to directory: URL) -> Bool {
    guard let data = downloadThumbnail(asset) else {
        return false
    }
    let destination = directory.appendingPathComponent(asset.filename)
    return (try? data.write(to: destination)) != nil
}
```

> Note: this reuses `downloadThumbnail` for the full-resolution pull in the POC — there is no separate thumbnail-vs-full-size distinction on the device side yet (that would need real on-device JPEG downsampling, out of scope per the spec's "Out of Scope" section). `download(to:)` and `downloadThumbnail` differ only in destination (disk vs. in-memory `Data`), matching the Data-axis split in the story map.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test -only-testing:ip3gsTests/DeviceBridgeDownloadTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/ip3gs/DeviceBridge/DeviceBridge.swift Tests/ip3gsTests/DeviceBridgeDownloadTests.swift
git commit -m "feat: add DeviceBridge thumbnail and download"
```

---

### Task 5: `PhotoLibrary` orchestration + error-state rules

**Files:**
- Create: `Sources/ip3gs/PhotoLibrary.swift`
- Test: `Tests/ip3gsTests/PhotoLibraryTests.swift`

**Interfaces:**
- Consumes: `DeviceState`, `PhotoAsset`, `DeviceBridge` (Tasks 2–4) — via a `DeviceBridging` protocol so tests use a fake, not the real `DeviceBridge`
- Produces:
  - `protocol DeviceBridging { func checkConnection() -> DeviceState; func listPhotos(udid: String) -> [PhotoAsset]; func downloadThumbnail(_ asset: PhotoAsset) -> Data?; func download(_ asset: PhotoAsset, to directory: URL) -> Bool }`
  - `final class PhotoLibrary: ObservableObject { @Published var statusText: String; @Published var assets: [PhotoAsset]; @Published var thumbnails: [String: Data]; @Published var failedDownloads: [String]; func refresh(); func downloadAll(to directory: URL) }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ip3gs

private final class FakeBridge: DeviceBridging {
    var state: DeviceState = .notConnected
    var assets: [PhotoAsset] = []
    var thumbnailsByFilename: [String: Data] = [:]
    var downloadResults: [String: Bool] = [:]

    func checkConnection() -> DeviceState { state }
    func listPhotos(udid: String) -> [PhotoAsset] { assets }
    func downloadThumbnail(_ asset: PhotoAsset) -> Data? { thumbnailsByFilename[asset.filename] }
    func download(_ asset: PhotoAsset, to directory: URL) -> Bool { downloadResults[asset.filename] ?? true }
}

final class PhotoLibraryTests: XCTestCase {
    func testRefreshWithNoDeviceSetsStatus() {
        let bridge = FakeBridge()
        bridge.state = .notConnected
        let library = PhotoLibrary(bridge: bridge)

        library.refresh()

        XCTAssertEqual(library.statusText, "No device connected")
        XCTAssertEqual(library.assets, [])
    }

    func testRefreshWithUntrustedDeviceSetsStatus() {
        let bridge = FakeBridge()
        bridge.state = .untrusted
        let library = PhotoLibrary(bridge: bridge)

        library.refresh()

        XCTAssertEqual(library.statusText, "Trust this computer on the iPhone")
    }

    func testRefreshWithConnectedDeviceLoadsAssetsAndThumbnails() {
        let bridge = FakeBridge()
        let asset = PhotoAsset(id: "IMG_0001.JPG", filename: "IMG_0001.JPG", remotePath: "/DCIM/100APPLE/IMG_0001.JPG")
        bridge.state = .connected(udid: "abc123")
        bridge.assets = [asset]
        bridge.thumbnailsByFilename = ["IMG_0001.JPG": Data([0x01])]
        let library = PhotoLibrary(bridge: bridge)

        library.refresh()

        XCTAssertEqual(library.assets, [asset])
        XCTAssertEqual(library.thumbnails["IMG_0001.JPG"], Data([0x01]))
        XCTAssertEqual(library.statusText, "1 photo found")
    }

    func testDownloadAllSkipsFailuresAndListsThem() {
        let bridge = FakeBridge()
        let good = PhotoAsset(id: "IMG_0001.JPG", filename: "IMG_0001.JPG", remotePath: "/DCIM/100APPLE/IMG_0001.JPG")
        let bad = PhotoAsset(id: "IMG_0002.JPG", filename: "IMG_0002.JPG", remotePath: "/DCIM/100APPLE/IMG_0002.JPG")
        bridge.state = .connected(udid: "abc123")
        bridge.assets = [good, bad]
        bridge.downloadResults = ["IMG_0001.JPG": true, "IMG_0002.JPG": false]
        let library = PhotoLibrary(bridge: bridge)
        library.refresh()

        library.downloadAll(to: URL(fileURLWithPath: "/tmp/ip3gs-test"))

        XCTAssertEqual(library.failedDownloads, ["IMG_0002.JPG"])
        XCTAssertEqual(library.statusText, "Downloaded 1 of 2 (1 failed)")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test -only-testing:ip3gsTests/PhotoLibraryTests`
Expected: FAIL — `DeviceBridging` and `PhotoLibrary` do not exist yet.

- [ ] **Step 3: Write `PhotoLibrary.swift`**

```swift
import Foundation

protocol DeviceBridging {
    func checkConnection() -> DeviceState
    func listPhotos(udid: String) -> [PhotoAsset]
    func downloadThumbnail(_ asset: PhotoAsset) -> Data?
    func download(_ asset: PhotoAsset, to directory: URL) -> Bool
}

extension DeviceBridge: DeviceBridging {}

final class PhotoLibrary: ObservableObject {
    @Published var statusText: String = "No device connected"
    @Published var assets: [PhotoAsset] = []
    @Published var thumbnails: [String: Data] = [:]
    @Published var failedDownloads: [String] = []

    private let bridge: DeviceBridging

    init(bridge: DeviceBridging) {
        self.bridge = bridge
    }

    func refresh() {
        switch bridge.checkConnection() {
        case .notConnected:
            statusText = "No device connected"
            assets = []
        case .untrusted:
            statusText = "Trust this computer on the iPhone"
            assets = []
        case .connected(let udid):
            assets = bridge.listPhotos(udid: udid)
            for asset in assets {
                thumbnails[asset.filename] = bridge.downloadThumbnail(asset)
            }
            statusText = "\(assets.count) photo\(assets.count == 1 ? "" : "s") found"
        }
    }

    func downloadAll(to directory: URL) {
        failedDownloads = []
        var succeeded = 0

        for asset in assets {
            if bridge.download(asset, to: directory) {
                succeeded += 1
            } else {
                failedDownloads.append(asset.filename)
            }
        }

        statusText = failedDownloads.isEmpty
            ? "Downloaded \(succeeded) of \(assets.count)"
            : "Downloaded \(succeeded) of \(assets.count) (\(failedDownloads.count) failed)"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test -only-testing:ip3gsTests/PhotoLibraryTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/ip3gs/PhotoLibrary.swift Tests/ip3gsTests/PhotoLibraryTests.swift
git commit -m "feat: add PhotoLibrary orchestration and error-state rules"
```

---

### Task 6: SwiftUI views

**Files:**
- Modify: `Sources/ip3gs/ip3gsApp.swift`
- Modify: `Sources/ip3gs/ContentView.swift`

**Interfaces:**
- Consumes: `PhotoLibrary` (Task 5), `PhotoAsset` (Task 3)
- Produces: no new public interface — this is the leaf UI layer.

- [ ] **Step 1: Update `ip3gsApp.swift` to construct the real `DeviceBridge`-backed `PhotoLibrary`**

```swift
import SwiftUI

@main
struct ip3gsApp: App {
    @StateObject private var library = PhotoLibrary(bridge: DeviceBridge())

    var body: some Scene {
        WindowGroup {
            ContentView(library: library)
        }
    }
}
```

- [ ] **Step 2: Rewrite `ContentView.swift`**

```swift
import SwiftUI

struct ContentView: View {
    @ObservedObject var library: PhotoLibrary

    private let columns = [GridItem(.adaptive(minimum: 100))]

    var body: some View {
        VStack(spacing: 0) {
            Text(library.statusText)
                .font(.callout)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(library.assets) { asset in
                        thumbnail(for: asset)
                    }
                }
                .padding(8)
            }

            Button("Download All") {
                let destination = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Pictures/ip3gs")
                try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                library.downloadAll(to: destination)
            }
            .padding(8)
            .disabled(library.assets.isEmpty)
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear { library.refresh() }
    }

    @ViewBuilder
    private func thumbnail(for asset: PhotoAsset) -> some View {
        if let data = library.thumbnails[asset.filename], let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 100, height: 100)
        }
    }
}

#Preview {
    ContentView(library: PhotoLibrary(bridge: DeviceBridge()))
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run full test suite to verify no regressions**

Run: `xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test`
Expected: `** TEST SUCCEEDED **` (all prior tests still pass — this task adds no new tests, per the "leaf UI layer, no new interface" note above)

- [ ] **Step 5: Commit**

```bash
git add Sources/ip3gs/ip3gsApp.swift Sources/ip3gs/ContentView.swift
git commit -m "feat: wire SwiftUI status bar, thumbnail grid, and download button"
```

---

### Task 7: Wire-up, manual device verification, docs

**Files:**
- Modify: `CLAUDE.md`
- Modify: `Sources/ip3gs/DeviceBridge/DeviceBridge.swift` (only if the spike reveals the assumed CLI contract from Tasks 2–4 is wrong)

**Interfaces:**
- Consumes: everything built in Tasks 1–6.
- Produces: nothing new — this task validates the assumed `ideviceinfo` / `afcclient` output contract against a real iPhone 3GS, since Tasks 2–4 wrote parsing logic against a documented assumption (see spec's "Testing Approach" section) rather than an observed one.

- [ ] **Step 1: Run setup and build**

Run: `./Tools/setup.sh && xcodegen generate && xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Connect a real iPhone 3GS via USB and launch the app**

Run: `open /path/to/DerivedData/.../ip3gs.app` (path printed by the build step above)
Expected: status bar reads "Trust this computer on the iPhone" on first connect, then updates to "N photos found" after trusting.

- [ ] **Step 3: If `ideviceinfo`/`afcclient` output doesn't match Tasks 2–4's assumed format, fix the parsing**

Compare actual output:
```bash
Tools/bin/ideviceinfo
Tools/bin/afcclient -u <udid> ls /DCIM/100APPLE
```
against the parsing logic in `DeviceBridge.swift`. If they differ, update the parsing code (not the test fakes — the fakes encode the *assumed* contract; if reality differs, the tests must be updated to match reality, then re-run to confirm they still pass with corrected fixtures).

- [ ] **Step 4: Click "Download All" and confirm files land in `~/Pictures/ip3gs/`**

Run: `ls ~/Pictures/ip3gs/`
Expected: photo files present, matching what's shown in the grid.

- [ ] **Step 5: Update `CLAUDE.md`'s "Notes for future sessions" section**

Replace the placeholder note with real structure info:

```markdown
## Notes for future sessions

- Run `./Tools/setup.sh` once to vendor libimobiledevice binaries into `Tools/bin/` (gitignored, never installed globally).
- `xcodegen generate` before opening/building after any `project.yml` change.
- Module layout: `Sources/ip3gs/DeviceBridge/` (device I/O, shells out to `Tools/bin/*`), `Sources/ip3gs/PhotoLibrary.swift` (app state/rules), root-level SwiftUI views.
- The app talks to the device only through vendored CLI binaries (`ideviceinfo`, `afcclient`) via `Process` — no C interop, no global libimobiledevice install.
```

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md Sources/ip3gs/DeviceBridge/DeviceBridge.swift
git commit -m "docs: confirm device wiring against real hardware, update CLAUDE.md"
```

---

## Self-Review Notes

- **Spec coverage:** Vendoring (Task 1) ✅, connection check (Task 2) ✅, listing (Task 3) ✅, thumbnail+download (Task 4) ✅, error-state rules (Task 5) ✅, minimal UI (Task 6) ✅, real-device validation of the assumed CLI contract (Task 7) ✅. Out-of-scope items from the spec are not addressed anywhere in this plan, as intended.
- **Type consistency:** `PhotoAsset`, `DeviceState`, `ProcessRunning`, `DeviceBridging` signatures are identical everywhere they're consumed across Tasks 2–6.
- **Known risk carried forward:** Tasks 2–4 write `afcclient`/`ideviceinfo` argument and output parsing against a *documented assumption*, not an observed real-device output — Task 7 exists specifically to close that gap. This is called out explicitly rather than hidden.
