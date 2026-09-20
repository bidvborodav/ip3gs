# Task 5 — `PhotoLibrary` orchestration + error-state rules

**Axis:** Rules. Encodes the business rules (not-connected / untrusted /
per-file-failure-is-non-fatal) on top of the mechanical layers in Tasks 2–4.

**Status:** Done as briefed (2026-09-20).

**Files:** create `Sources/ip3gs/PhotoLibrary.swift`; test
`Tests/ip3gsTests/PhotoLibraryTests.swift`.

**Consumes:** `DeviceState`, `PhotoAsset`, `DeviceBridge` — via a
`DeviceBridging` protocol so tests use a fake, not the real bridge.

- [ ] **Step 1: `PhotoLibrary.swift`**

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

**Known POC shortcut:** `refresh()` fetches every thumbnail synchronously on
the calling thread. The design spec calls for background fetches that populate
the grid incrementally; this blocks instead. Acceptable for a first pass on a
small library, visibly wrong on a large one.

- [ ] **Step 2: verification test** (after the code)

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

- [ ] **Step 3: run** — `-only-testing:ip3gsTests/PhotoLibraryTests` → PASS (4 tests)

- [ ] **Step 4: commit** — `feat: add PhotoLibrary orchestration and error-state rules`
