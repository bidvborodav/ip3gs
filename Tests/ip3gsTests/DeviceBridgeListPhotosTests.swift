import XCTest
@testable import ip3gs

private struct FakeRunner: ProcessRunning {
    let stdout: String

    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: Data, stderr: String, exitCode: Int32) {
        (Data(stdout.utf8), "", 0)
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
