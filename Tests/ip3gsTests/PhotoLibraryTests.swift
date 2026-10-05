import XCTest
@testable import ip3gs

// Called from background threads by PhotoLibrary, so its counters are lock-guarded.
private final class FakeBridge: DeviceBridging, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var checks = 0

    var state: DeviceState = .notConnected
    var assets: [PhotoAsset] = []
    var downloadResults: [String: Bool] = [:]
    var downloadDelay: TimeInterval = 0
    let payload = makeJPEG(width: 400, height: 300)

    var downloadCounts: [String: Int] { lock.withLock { counts } }
    var totalDownloads: Int { lock.withLock { counts.values.reduce(0, +) } }
    var checkCount: Int { lock.withLock { checks } }

    func checkConnection() -> DeviceState {
        lock.withLock { checks += 1 }
        return state
    }

    func listPhotos(udid: String) -> [PhotoAsset] { assets }

    func download(_ asset: PhotoAsset, to directory: URL) -> Bool {
        if downloadDelay > 0 { Thread.sleep(forTimeInterval: downloadDelay) }
        lock.withLock { counts[asset.filename, default: 0] += 1 }
        guard downloadResults[asset.filename] ?? true else { return false }
        return (try? payload.write(to: directory.appendingPathComponent(asset.filename))) != nil
    }
}

private func asset(_ name: String) -> PhotoAsset {
    PhotoAsset(id: name, filename: name, remotePath: "/DCIM/100APPLE/\(name)")
}

private func assets(_ count: Int, ext: String) -> [PhotoAsset] {
    (1...count).map { asset(String(format: "IMG_%04d.%@", $0, ext)) }
}

@MainActor
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

    private func connectedBridge(_ assets: [PhotoAsset], delay: TimeInterval = 0) -> FakeBridge {
        let bridge = FakeBridge()
        bridge.state = .connected(udid: "abc123")
        bridge.assets = assets
        bridge.downloadDelay = delay
        return bridge
    }

    /// Polls on the main actor until `condition` holds; fails the test after ~5 s.
    private func waitUntil(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for \(message)")
    }

    func testRefreshWithNoDeviceSetsStatus() async {
        let bridge = FakeBridge()
        bridge.state = .notConnected
        let library = makeLibrary(bridge)

        await library.refresh()

        XCTAssertEqual(library.statusText, "No device connected")
        XCTAssertEqual(library.assets, [])
    }

    func testRefreshWithUntrustedDeviceSetsStatus() async {
        let bridge = FakeBridge()
        bridge.state = .untrusted
        let library = makeLibrary(bridge)

        await library.refresh()

        XCTAssertEqual(library.statusText, "Trust this computer on the iPhone")
    }

    func testRefreshWithConnectedDeviceLoadsAssetsAndThumbnails() async {
        let bridge = connectedBridge([asset("IMG_0001.JPG")])
        let library = makeLibrary(bridge)

        await library.refresh()

        XCTAssertEqual(library.assets, [asset("IMG_0001.JPG")])
        let thumbnail = library.thumbnails["IMG_0001.JPG"]
        XCTAssertNotNil(thumbnail.flatMap { NSImage(data: $0) }, "thumbnail must be a decodable image")
        XCTAssertEqual(library.statusText, "1 photo found")
        XCTAssertNil(library.progress)
    }

    func testRefreshDoesNotPullVideos() async {
        let bridge = connectedBridge([asset("IMG_0001.JPG"), asset("IMG_0002.MOV")])
        let library = makeLibrary(bridge)

        await library.refresh()

        XCTAssertNil(bridge.downloadCounts["IMG_0002.MOV"])
        XCTAssertNil(library.thumbnails["IMG_0002.MOV"])
        XCTAssertEqual(library.statusText, "2 photos found")
    }

    func testDownloadAllReusesTheCacheSoEachPhotoIsPulledOnce() async throws {
        let bridge = connectedBridge([asset("IMG_0001.JPG"), asset("IMG_0002.JPG")])
        let library = makeLibrary(bridge)
        await library.refresh()

        await library.downloadAll(to: destination)

        XCTAssertEqual(bridge.downloadCounts, ["IMG_0001.JPG": 1, "IMG_0002.JPG": 1])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted(),
                       ["IMG_0001.JPG", "IMG_0002.JPG"])
        XCTAssertEqual(library.statusText, "Downloaded 2 of 2")
    }

    func testDownloadAllStillPullsVideos() async {
        let bridge = connectedBridge([asset("IMG_0001.JPG"), asset("IMG_0002.MOV")])
        let library = makeLibrary(bridge)
        await library.refresh()

        await library.downloadAll(to: destination)

        XCTAssertEqual(bridge.downloadCounts["IMG_0002.MOV"], 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("IMG_0002.MOV").path))
    }

    func testDownloadAllSkipsFailuresAndListsThem() async {
        let bridge = connectedBridge([asset("IMG_0001.JPG"), asset("IMG_0002.JPG")])
        bridge.downloadResults = ["IMG_0001.JPG": true, "IMG_0002.JPG": false]
        let library = makeLibrary(bridge)
        await library.refresh()

        await library.downloadAll(to: destination)

        XCTAssertEqual(library.failedDownloads, ["IMG_0002.JPG"])
        XCTAssertEqual(library.statusText, "Downloaded 1 of 2 (1 failed)")
    }

    // Proof the main actor is free while the bridge blocks: a ticker on the main actor keeps
    // running, refresh is still going when it finishes, and thumbnails arrive one by one.
    func testMainActorStaysFreeAndThumbnailsArriveIncrementally() async throws {
        let bridge = connectedBridge(assets(20, ext: "JPG"), delay: 0.05)
        let library = makeLibrary(bridge)
        var finished = false
        let refresh = Task {
            await library.refresh()
            finished = true
        }

        var ticks = 0
        var thumbnailCounts: [Int] = []
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 20_000_000)
            ticks += 1
            thumbnailCounts.append(library.thumbnails.count)
        }

        XCTAssertEqual(ticks, 10)
        XCTAssertFalse(finished, "refresh should still be running after 200 ms of a ~1 s load")
        XCTAssertTrue(thumbnailCounts.contains { $0 > 0 && $0 < 20 }, "thumbnails were not incremental: \(thumbnailCounts)")
        await refresh.value
        XCTAssertEqual(library.thumbnails.count, 20)
    }

    func testCancelDuringRefreshStopsCleanly() async throws {
        let bridge = connectedBridge(assets(20, ext: "JPG"), delay: 0.05)
        let library = makeLibrary(bridge)

        library.startRefresh()
        try await waitUntil("3 pulls") { bridge.totalDownloads >= 3 }
        library.cancel()
        try await waitUntil("refresh to stop") { !library.isBusy }

        XCTAssertTrue(library.statusText.hasPrefix("Cancelled — "), library.statusText)
        XCTAssertLessThan(library.thumbnails.count, 20)
        XCTAssertNil(library.progress)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheRoot.appendingPathComponent("abc123/.partial").path),
                       "an interrupted pull must not leave a .partial directory behind")
    }

    func testCancelDuringDownloadAllStopsCleanly() async throws {
        // Videos are not cached, so every one is a slow direct pull, which gives cancel something to interrupt.
        let bridge = connectedBridge(assets(20, ext: "MOV"), delay: 0.05)
        let library = makeLibrary(bridge)
        await library.refresh()

        library.startDownloadAll(to: destination)
        try await waitUntil("3 pulls") { bridge.totalDownloads >= 3 }
        library.cancel()
        try await waitUntil("download to stop") { !library.isBusy }

        XCTAssertTrue(library.statusText.hasPrefix("Cancelled — downloaded "), library.statusText)
        let files = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        XCTAssertGreaterThanOrEqual(files.count, 3)
        XCTAssertLessThan(files.count, 20)
        for file in files {
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(file)), bridge.payload, "\(file) is incomplete")
        }
        XCTAssertNil(library.progress)
    }

    func testStartRefreshWhileBusyIsIgnored() async throws {
        let bridge = FakeBridge()
        bridge.state = .notConnected
        let library = makeLibrary(bridge)

        library.startRefresh()
        library.startRefresh()
        try await waitUntil("refresh to finish") { !library.isBusy }

        XCTAssertEqual(bridge.checkCount, 1)
    }
}
