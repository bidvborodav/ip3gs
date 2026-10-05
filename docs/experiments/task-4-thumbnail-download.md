# Task 4 — Thumbnail & download

**Axis:** Data. Same shape as Task 3 but a different payload (binary file
contents vs. text listing) and a different destination (memory vs. disk).

**Status:** Done, but **this brief's code is stale** — its `afcclient`/`ideviceinfo` contract was falsified from source. Follow [`../domain.md`](../domain.md#tool-interfaces-verified-from-source) and the code.

**Files:** modify `Sources/ip3gs/DeviceBridge/DeviceBridge.swift`; test
`Tests/ip3gsTests/DeviceBridgeDownloadTests.swift`.

**Consumes:** `PhotoAsset` (Task 3), `ProcessRunning` (Task 2).

> ⚠️ **Read [`../research.md`](../research.md) Q4 before starting.** The code
> below round-trips binary JPEG bytes through a `String` stdout pipe. That is
> expected to corrupt any non-UTF-8 payload — which is every real photo. The
> likely correct fix is widening `ProcessRunning` to return `Data` rather than
> `String`, which touches Task 2's protocol and everything built on it. Decide
> this deliberately rather than discovering it at Task 7.

> **Placement:** add both methods *inside* the existing
> `final class DeviceBridge { ... }` body — not as an extension. `binDir` and
> `runner` are `private`. (This was the pre-flight ruling recorded in the
> ledger; it is now stated here directly.)

- [ ] **Step 1: add `downloadThumbnail` and `download(to:)`**

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

Two known shortcuts, both deliberate:

- **No real thumbnailing.** This reuses the full-resolution pull for the grid;
  there is no cheap on-device thumbnail to fetch
  ([`../domain.md`](../domain.md#photo-library-layout)). Downsampling locally
  is out of scope for the POC.
- **Empty `-u ""` udid.** Unlike `listPhotos`, these methods do not thread the
  udid through. Whether `afcclient` tolerates that is untested.

- [ ] **Step 2: verification test** (after the code)

```swift
import XCTest
@testable import ip3gs

private struct FakeRunner: ProcessRunning {
    let stdoutData: String
    let exitCode: Int32

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

Note these fixtures all use UTF-8-safe ASCII payloads, so they will pass even
if the binary-through-`String` problem above is real. They do not protect you.

- [ ] **Step 3: run** — `-only-testing:ip3gsTests/DeviceBridgeDownloadTests` → PASS (3 tests)

- [ ] **Step 4: commit** — `feat: add DeviceBridge thumbnail and download`
