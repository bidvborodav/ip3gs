import XCTest
@testable import ip3gs

private struct FakeRunner: ProcessRunning {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: Data, stderr: String, exitCode: Int32) {
        (Data(stdout.utf8), stderr, exitCode)
    }
}

final class DeviceBridgeConnectionTests: XCTestCase {
    func testNoDeviceConnected() {
        let runner = FakeRunner(stdout: "", stderr: "No device found.", exitCode: 1)
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)
        XCTAssertEqual(bridge.checkConnection(), .notConnected)
    }

    func testUntrustedDevice() {
        let runner = FakeRunner(stdout: "", stderr: "ERROR: Could not connect to lockdownd, error code -18", exitCode: 1)
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)
        XCTAssertEqual(bridge.checkConnection(), .untrusted)
    }

    func testConnectedDevice() {
        let stdout = "DeviceName: iPhone\nUniqueDeviceID: abc123\nProductVersion: 6.1.6\n"
        let runner = FakeRunner(stdout: stdout, stderr: "", exitCode: 0)
        let bridge = DeviceBridge(binDir: "Tools/bin", runner: runner)
        XCTAssertEqual(bridge.checkConnection(), .connected(udid: "abc123"))
    }
}

final class SystemProcessRunnerTests: XCTestCase {
    func testLargeBinaryOutputSurvivesIntact() throws {
        // 200 KB of non-UTF-8 bytes: exceeds the pipe buffer and cannot round-trip through String.
        let (stdout, _, exitCode) = try SystemProcessRunner().run(
            "/usr/bin/head", arguments: ["-c", "200000", "/dev/urandom"]
        )
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout.count, 200_000)
    }
}
