import XCTest
@testable import ip3gs

final class DeviceBridgeListPhotosTests: XCTestCase {
    func testParsesPromptedAnsiOutputIntoAssets() {
        let runner = FakeRunner(stdout: afcOutput(entries: ["IMG_0001.JPG", "IMG_0002.JPG"]))
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)

        XCTAssertEqual(bridge.listPhotos(udid: "abc123"), [
            PhotoAsset(id: "IMG_0001.JPG", filename: "IMG_0001.JPG", remotePath: "/DCIM/100APPLE/IMG_0001.JPG"),
            PhotoAsset(id: "IMG_0002.JPG", filename: "IMG_0002.JPG", remotePath: "/DCIM/100APPLE/IMG_0002.JPG"),
        ])
    }

    func testEmptyDirectoryReturnsNoAssets() {
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: FakeRunner(stdout: afcOutput(entries: [])))

        XCTAssertEqual(bridge.listPhotos(udid: "abc123"), [])
    }

    func testAfcErrorLineReturnsNoAssets() {
        let runner = FakeRunner(stdout: afcOutput(entries: ["Error: Failed to list '/DCIM/100APPLE': Object not found (8)"]))
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)

        XCTAssertEqual(bridge.listPhotos(udid: "abc123"), [])
    }

    func testCommandsAreSentOnStdinTerminatedByQuit() {
        let recorder = Recorder()
        let runner = FakeRunner { arguments, stdin in
            recorder.arguments = arguments
            recorder.stdin = stdin
            return (Data(), "", 0)
        }

        _ = DeviceBridge(binDir: "Tools/bin", runner: runner).listPhotos(udid: "abc123")

        XCTAssertEqual(recorder.arguments, ["-u", "abc123"])
        XCTAssertEqual(recorder.stdin, "ls \"/DCIM/100APPLE\"\nquit\n")
    }
}
