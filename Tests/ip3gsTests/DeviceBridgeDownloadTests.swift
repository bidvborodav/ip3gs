import XCTest
@testable import ip3gs

private struct FakeRunner: ProcessRunning {
    let stdoutData: Data
    let exitCode: Int32

    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: Data, stderr: String, exitCode: Int32) {
        (stdoutData, "", exitCode)
    }
}

private let asset = PhotoAsset(id: "IMG_0001.JPG", filename: "IMG_0001.JPG", remotePath: "/DCIM/100APPLE/IMG_0001.JPG")

// Not valid UTF-8: proves binary payloads survive the runner boundary.
private let jpegLikeBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x80, 0xC0, 0xFE, 0xFF, 0xD9])

final class DeviceBridgeDownloadTests: XCTestCase {
    func testDownloadThumbnailReturnsBinaryDataIntact() {
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: FakeRunner(stdoutData: jpegLikeBytes, exitCode: 0))

        XCTAssertEqual(bridge.downloadThumbnail(asset), jpegLikeBytes)
    }

    func testDownloadThumbnailFailureReturnsNil() {
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: FakeRunner(stdoutData: Data(), exitCode: 1))

        XCTAssertNil(bridge.downloadThumbnail(asset))
    }

    func testDownloadThumbnailEmptyOutputReturnsNil() {
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: FakeRunner(stdoutData: Data(), exitCode: 0))

        XCTAssertNil(bridge.downloadThumbnail(asset))
    }

    func testDownloadWritesFileToDirectory() throws {
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: FakeRunner(stdoutData: jpegLikeBytes, exitCode: 0))
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        XCTAssertTrue(bridge.download(asset, to: tempDir))

        XCTAssertEqual(try Data(contentsOf: tempDir.appendingPathComponent("IMG_0001.JPG")), jpegLikeBytes)
    }
}
