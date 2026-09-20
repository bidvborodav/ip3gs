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

        let stdout = String(decoding: result.stdout, as: UTF8.self)
        for line in stdout.split(separator: "\n") {
            if line.hasPrefix("UniqueDeviceID:") {
                let udid = line.replacingOccurrences(of: "UniqueDeviceID:", with: "").trimmingCharacters(in: .whitespaces)
                return .connected(udid: udid)
            }
        }

        return .notConnected
    }
}
