import XCTest
@testable import ip3gs

private final class FakeBridge: DeviceBridging {
    var state: DeviceState = .notConnected
    var assets: [PhotoAsset] = []
    var downloadResults: [String: Bool] = [:]
    var downloadCounts: [String: Int] = [:]
    let payload = Data([0x01])

    func checkConnection() -> DeviceState { state }
    func listPhotos(udid: String) -> [PhotoAsset] { assets }
    func download(_ asset: PhotoAsset, to directory: URL) -> Bool {
        downloadCounts[asset.filename, default: 0] += 1
        guard downloadResults[asset.filename] ?? true else { return false }
        return (try? payload.write(to: directory.appendingPathComponent(asset.filename))) != nil
    }
}

private func asset(_ name: String) -> PhotoAsset {
    PhotoAsset(id: name, filename: name, remotePath: "/DCIM/100APPLE/\(name)")
}

final class PhotoLibraryTests: XCTestCase {
    private var cacheRoot: URL!
    private var destination: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cacheRoot = base.appendingPathComponent("cache")
        destination = base.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
    }

    private func makeLibrary(_ bridge: FakeBridge) -> PhotoLibrary {
        PhotoLibrary(bridge: bridge, cacheRoot: cacheRoot)
    }

    func testRefreshWithNoDeviceSetsStatus() {
        let bridge = FakeBridge()
        bridge.state = .notConnected
        let library = makeLibrary(bridge)

        library.refresh()

        XCTAssertEqual(library.statusText, "No device connected")
        XCTAssertEqual(library.assets, [])
    }

    func testRefreshWithUntrustedDeviceSetsStatus() {
        let bridge = FakeBridge()
        bridge.state = .untrusted
        let library = makeLibrary(bridge)

        library.refresh()

        XCTAssertEqual(library.statusText, "Trust this computer on the iPhone")
    }

    func testRefreshWithConnectedDeviceLoadsAssetsAndThumbnails() {
        let bridge = FakeBridge()
        bridge.state = .connected(udid: "abc123")
        bridge.assets = [asset("IMG_0001.JPG")]
        let library = makeLibrary(bridge)

        library.refresh()

        XCTAssertEqual(library.assets, [asset("IMG_0001.JPG")])
        XCTAssertEqual(library.thumbnails["IMG_0001.JPG"], bridge.payload)
        XCTAssertEqual(library.statusText, "1 photo found")
    }

    func testRefreshDoesNotPullVideos() {
        let bridge = FakeBridge()
        bridge.state = .connected(udid: "abc123")
        bridge.assets = [asset("IMG_0001.JPG"), asset("IMG_0002.MOV")]
        let library = makeLibrary(bridge)

        library.refresh()

        XCTAssertNil(bridge.downloadCounts["IMG_0002.MOV"])
        XCTAssertNil(library.thumbnails["IMG_0002.MOV"])
        XCTAssertEqual(library.statusText, "2 photos found")
    }

    func testDownloadAllReusesTheCacheSoEachPhotoIsPulledOnce() throws {
        let bridge = FakeBridge()
        bridge.state = .connected(udid: "abc123")
        bridge.assets = [asset("IMG_0001.JPG"), asset("IMG_0002.JPG")]
        let library = makeLibrary(bridge)
        library.refresh()

        library.downloadAll(to: destination)

        XCTAssertEqual(bridge.downloadCounts, ["IMG_0001.JPG": 1, "IMG_0002.JPG": 1])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted(),
                       ["IMG_0001.JPG", "IMG_0002.JPG"])
        XCTAssertEqual(library.statusText, "Downloaded 2 of 2")
    }

    func testDownloadAllStillPullsVideos() throws {
        let bridge = FakeBridge()
        bridge.state = .connected(udid: "abc123")
        bridge.assets = [asset("IMG_0001.JPG"), asset("IMG_0002.MOV")]
        let library = makeLibrary(bridge)
        library.refresh()

        library.downloadAll(to: destination)

        XCTAssertEqual(bridge.downloadCounts["IMG_0002.MOV"], 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("IMG_0002.MOV").path))
    }

    func testDownloadAllSkipsFailuresAndListsThem() {
        let bridge = FakeBridge()
        bridge.state = .connected(udid: "abc123")
        bridge.assets = [asset("IMG_0001.JPG"), asset("IMG_0002.JPG")]
        bridge.downloadResults = ["IMG_0001.JPG": true, "IMG_0002.JPG": false]
        let library = makeLibrary(bridge)
        library.refresh()

        library.downloadAll(to: destination)

        XCTAssertEqual(library.failedDownloads, ["IMG_0002.JPG"])
        XCTAssertEqual(library.statusText, "Downloaded 1 of 2 (1 failed)")
    }
}
