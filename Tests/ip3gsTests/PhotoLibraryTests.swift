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
