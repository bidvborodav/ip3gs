# Task 2 — `DeviceBridge.checkConnection()`

**Axis:** Path. The narrowest happy/known-error path through the device layer.

**Files:** create `Sources/ip3gs/DeviceBridge/ProcessRunning.swift`,
`Sources/ip3gs/DeviceBridge/DeviceBridge.swift`; test
`Tests/ip3gsTests/DeviceBridgeConnectionTests.swift`.

**Produces:** `ProcessRunning`, `SystemProcessRunner`, `DeviceState`,
`DeviceBridge(binDir:runner:)`, `checkConnection()`.

> Before writing this, read [`../research.md`](../research.md) Q4. The
> `String`-typed stdout in `ProcessRunning` below is known-suspect for the
> binary payloads Task 4 needs. Changing it later means changing every method
> built on it.

- [ ] **Step 1: `ProcessRunning.swift`**

```swift
import Foundation

protocol ProcessRunning {
    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32)
}

struct SystemProcessRunner: ProcessRunning {
    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return (
            String(data: stdoutData, encoding: .utf8) ?? "",
            String(data: stderrData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }
}
```

- [ ] **Step 2: `DeviceBridge.swift`**

```swift
import Foundation

enum DeviceState: Equatable {
    case notConnected
    case untrusted
    case connected(udid: String)
}

final class DeviceBridge {
    private let binDir: String
    private let runner: ProcessRunning

    init(binDir: String = "Tools/bin", runner: ProcessRunning = SystemProcessRunner()) {
        self.binDir = binDir
        self.runner = runner
    }

    func checkConnection() -> DeviceState {
        guard let result = try? runner.run("\(binDir)/ideviceinfo", arguments: []) else {
            return .notConnected
        }

        if result.exitCode != 0 {
            if result.stderr.contains("error code -18") {
                return .untrusted
            }
            return .notConnected
        }

        for line in result.stdout.split(separator: "\n") {
            if line.hasPrefix("UniqueDeviceID:") {
                let udid = line.replacingOccurrences(of: "UniqueDeviceID:", with: "").trimmingCharacters(in: .whitespaces)
                return .connected(udid: udid)
            }
        }

        return .notConnected
    }
}
```

- [ ] **Step 3: verification test** (written *after* the code — see
  [`../best-practices.md`](../best-practices.md#tdd-is-disabled-for-the-poc))

```swift
import XCTest
@testable import ip3gs

private struct FakeRunner: ProcessRunning {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    func run(_ executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        (stdout, stderr, exitCode)
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
```

- [ ] **Step 4: run** — `xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -destination 'platform=macOS' test -only-testing:ip3gsTests/DeviceBridgeConnectionTests` → PASS (3 tests)

- [ ] **Step 5: commit** — `feat: add DeviceBridge connection check`
