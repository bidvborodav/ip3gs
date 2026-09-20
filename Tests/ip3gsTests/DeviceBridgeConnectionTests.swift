import XCTest
@testable import ip3gs

final class DeviceBridgeConnectionTests: XCTestCase {
    private func state(stderr: String, exitCode: Int32 = 1, stdout: String = "") -> DeviceState {
        DeviceBridge(binDir: "Tools/bin", runner: FakeRunner(stdout: stdout, stderr: stderr, exitCode: exitCode)).checkConnection()
    }

    func testNoDeviceConnected() {
        XCTAssertEqual(state(stderr: "ERROR: No device found!"), .notConnected)
    }

    func testTrustDialogPendingIsUntrusted() {
        XCTAssertEqual(state(stderr: "ERROR: Could not connect to lockdownd: pairing dialog response pending (-19)"), .untrusted)
    }

    func testPairingDeniedIsUntrusted() {
        XCTAssertEqual(state(stderr: "ERROR: Could not connect to lockdownd: user denied pairing (-18)"), .untrusted)
    }

    func testUnrelatedLockdownErrorIsNotUntrusted() {
        XCTAssertEqual(state(stderr: "ERROR: Could not connect to lockdownd: mux error (-8)"), .notConnected)
    }

    func testConnectedDevice() {
        let stdout = "DeviceName: iPhone\nUniqueDeviceID: abc123\nProductVersion: 6.1.6\n"
        XCTAssertEqual(state(stderr: "", exitCode: 0, stdout: stdout), .connected(udid: "abc123"))
    }
}

final class SystemProcessRunnerTests: XCTestCase {
    func testLargeBinaryOutputSurvivesIntact() throws {
        // 200 KB of non-UTF-8 bytes: exceeds the pipe buffer and cannot round-trip through String.
        let (stdout, _, exitCode) = try SystemProcessRunner().run(
            "/usr/bin/head", arguments: ["-c", "200000", "/dev/urandom"], stdin: nil
        )
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout.count, 200_000)
    }

    func testStdinIsDeliveredToChild() throws {
        let (stdout, _, _) = try SystemProcessRunner().run("/bin/cat", arguments: [], stdin: "ls /\nquit\n")
        XCTAssertEqual(String(decoding: stdout, as: UTF8.self), "ls /\nquit\n")
    }
}
