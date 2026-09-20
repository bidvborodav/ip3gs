import XCTest
@testable import ip3gs

// Needs a trusted iPhone attached over USB. Run with:
//   TEST_RUNNER_IP3GS_DEVICE=1 xcodebuild ... test -only-testing:ip3gsTests/DeviceIntegrationTests
final class DeviceIntegrationTests: XCTestCase {
    private var bridge: DeviceBridge!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IP3GS_DEVICE"] != nil, "set IP3GS_DEVICE to run against hardware")
        let binDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tools/bin").path
        bridge = DeviceBridge(binDir: binDir)
    }

    private func connectedUDID() throws -> String {
        guard case .connected(let udid) = bridge.checkConnection() else {
            throw XCTSkip("no trusted device connected")
        }
        return udid
    }

    func testReportsConnectedWithUdid() {
        guard case .connected(let udid) = bridge.checkConnection() else {
            return XCTFail("expected .connected, got \(bridge.checkConnection())")
        }
        XCTAssertEqual(udid.count, 40, "3GS UDIDs are 40 hex characters")
    }

    func testListsPhotosUnderDCIM() throws {
        let assets = bridge.listPhotos(udid: try connectedUDID())

        XCTAssertFalse(assets.isEmpty)
        XCTAssertTrue(assets.allSatisfy { $0.remotePath.hasPrefix("/DCIM/100APPLE/") && !$0.filename.contains("\u{1B}") && !$0.filename.contains("afc:") })
    }

    func testDownloadedJPEGIsIntact() throws {
        let assets = bridge.listPhotos(udid: try connectedUDID())
        let jpeg = try XCTUnwrap(assets.first { $0.filename.uppercased().hasSuffix(".JPG") })
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertTrue(bridge.download(jpeg, to: dir))

        let data = try Data(contentsOf: dir.appendingPathComponent(jpeg.filename))
        XCTAssertGreaterThan(data.count, 10_000)
        XCTAssertEqual(Array(data.prefix(3)), [0xFF, 0xD8, 0xFF], "JPEG SOI marker")
        XCTAssertEqual(Array(data.suffix(2)), [0xFF, 0xD9], "JPEG EOI marker")
    }

    func testFullLibraryRefreshAndDownloadAll() throws {
        _ = try connectedUDID()
        let library = PhotoLibrary(bridge: bridge)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let refreshStart = Date()
        library.refresh()
        let refreshSeconds = Date().timeIntervalSince(refreshStart)

        let downloadStart = Date()
        library.downloadAll(to: dir)
        let downloadSeconds = Date().timeIntervalSince(downloadStart)

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let missingThumbs = library.assets.filter { library.thumbnails[$0.filename] == nil }.map(\.filename)
        print("DEVICE_REPORT assets=\(library.assets.count) refreshSeconds=\(Int(refreshSeconds)) downloadSeconds=\(Int(downloadSeconds)) files=\(files.count) failed=\(library.failedDownloads) missingThumbs=\(missingThumbs) status=\(library.statusText)")

        XCTAssertFalse(library.assets.isEmpty)
        XCTAssertEqual(files.count, library.assets.count - library.failedDownloads.count)
    }

    func testMissingFileFailsCleanly() throws {
        _ = try connectedUDID()
        let ghost = PhotoAsset(id: "NOPE.JPG", filename: "NOPE.JPG", remotePath: "/DCIM/100APPLE/NOPE.JPG")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertFalse(bridge.download(ghost, to: dir))
    }
}
