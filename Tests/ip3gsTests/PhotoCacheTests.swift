import XCTest
@testable import ip3gs

private final class CountingBridge: DeviceBridging, @unchecked Sendable {
    var downloadCount = 0
    var succeeds = true
    var payload = Data([0xFF, 0xD8, 0xFF])

    func checkConnection() -> DeviceState { .notConnected }
    func listPhotos(udid: String) -> [PhotoAsset] { [] }
    func downloadThumbnail(_ asset: PhotoAsset) -> Data? { nil }
    func download(_ asset: PhotoAsset, to directory: URL) -> Bool {
        downloadCount += 1
        guard succeeds else { return false }
        return (try? payload.write(to: directory.appendingPathComponent(asset.filename))) != nil
    }
}

final class PhotoCacheTests: XCTestCase {
    private var root: URL!
    private let asset = PhotoAsset(id: "IMG_0001.JPG", filename: "IMG_0001.JPG", remotePath: "/DCIM/100APPLE/IMG_0001.JPG")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeCache() -> PhotoCache {
        PhotoCache(directory: root.appendingPathComponent("cache"))
    }

    func testFillOnMissPullsOnceAndReturnsFile() throws {
        let bridge = CountingBridge()
        let cache = makeCache()

        let file = cache.fill(asset, using: bridge)

        XCTAssertEqual(bridge.downloadCount, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(file)), bridge.payload)
    }

    func testFillOnHitDoesNotTouchTheBridge() {
        let bridge = CountingBridge()
        let cache = makeCache()
        _ = cache.fill(asset, using: bridge)

        let file = cache.fill(asset, using: bridge)

        XCTAssertNotNil(file)
        XCTAssertEqual(bridge.downloadCount, 1)
    }

    func testFailedPullReturnsNilAndCachesNothing() {
        let bridge = CountingBridge()
        bridge.succeeds = false
        let cache = makeCache()

        XCTAssertNil(cache.fill(asset, using: bridge))
        XCTAssertFalse(cache.contains(asset))
    }

    func testStalePartialFromAnInterruptedRunIsNotAHit() throws {
        let cache = makeCache()
        let partial = cache.directory.appendingPathComponent(".partial")
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try Data([0x00]).write(to: partial.appendingPathComponent(asset.filename))
        let bridge = CountingBridge()

        XCTAssertFalse(cache.contains(asset))
        let file = cache.fill(asset, using: bridge)

        XCTAssertEqual(bridge.downloadCount, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(file)), bridge.payload)
    }

    func testCopyWritesCachedFileOverAnExistingOne() throws {
        let bridge = CountingBridge()
        let cache = makeCache()
        _ = cache.fill(asset, using: bridge)
        let destination = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data([0x00]).write(to: destination.appendingPathComponent(asset.filename))

        XCTAssertTrue(cache.copy(asset, to: destination))

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(asset.filename)), bridge.payload)
    }

    func testCopyOnMissReturnsFalse() {
        XCTAssertFalse(makeCache().copy(asset, to: root))
    }
}
