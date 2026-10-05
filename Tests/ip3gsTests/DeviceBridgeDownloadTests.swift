import XCTest
@testable import ip3gs

private let asset = PhotoAsset(id: "IMG_0001.JPG", filename: "IMG_0001.JPG", remotePath: "/DCIM/100APPLE/IMG_0001.JPG")

// Not valid UTF-8: proves binary payloads survive intact.
private let jpegLikeBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x80, 0xC0, 0xFE, 0xFF, 0xD9])

// Stands in for afcclient: on `get -f "<remote>" "<dir>"` writes the payload to <dir>/<basename>,
// as the real tool does. Like the real tool it exits 0 whatever happens.
private func fakeAFC(payload: Data?, output: String = "", recorder: Recorder = Recorder()) -> FakeRunner {
    FakeRunner { arguments, stdin in
        recorder.arguments = arguments
        recorder.stdin = stdin
        let parts = (stdin ?? "").split(separator: "\"", omittingEmptySubsequences: false).map(String.init)
        if let payload, parts.count >= 4 {
            let destination = URL(fileURLWithPath: parts[3]).appendingPathComponent((parts[1] as NSString).lastPathComponent)
            try? payload.write(to: destination)
        }
        return (Data(output.utf8), "", 0)
    }
}

final class DeviceBridgeDownloadTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testDownloadWritesBinaryFileIntact() throws {
        let dir = try makeTempDir()
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: fakeAFC(payload: jpegLikeBytes))

        XCTAssertTrue(bridge.download(asset, to: dir))

        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("IMG_0001.JPG")), jpegLikeBytes)
    }

    func testDownloadSendsForcedGetThenQuitWithoutUdid() throws {
        let dir = try makeTempDir()
        let recorder = Recorder()
        _ = DeviceBridge(binDir: "Tools/bin", runner: fakeAFC(payload: jpegLikeBytes, recorder: recorder)).download(asset, to: dir)

        XCTAssertEqual(recorder.arguments, [])
        XCTAssertEqual(recorder.stdin, "get -f \"/DCIM/100APPLE/IMG_0001.JPG\" \"\(dir.path)\"\nquit\n")
    }

    func testDownloadFailsWhenAfcPrintsError() throws {
        let dir = try makeTempDir()
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: fakeAFC(payload: nil, output: afcOutput(entries: ["Error: Failed to open file (8)"])))

        XCTAssertFalse(bridge.download(asset, to: dir))
    }

    func testDownloadFailsWhenNoFileLands() throws {
        let dir = try makeTempDir()
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: fakeAFC(payload: nil))

        XCTAssertFalse(bridge.download(asset, to: dir))
    }

    func testDownloadFailsForZeroLengthFile() throws {
        let dir = try makeTempDir()
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: fakeAFC(payload: Data()))

        XCTAssertFalse(bridge.download(asset, to: dir))
    }
}
