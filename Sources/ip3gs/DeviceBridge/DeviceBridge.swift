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

    private static let dcimPath = "/DCIM/100APPLE"

    func listPhotos(udid: String) -> [PhotoAsset] {
        guard let result = try? runner.run("\(binDir)/afcclient", arguments: ["-u", udid, "ls", Self.dcimPath]) else {
            return []
        }

        return String(decoding: result.stdout, as: UTF8.self)
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
            .map { filename in
                PhotoAsset(id: filename, filename: filename, remotePath: "\(Self.dcimPath)/\(filename)")
            }
    }

    // [assumed] With no -u, afcclient targets the first connected device, and `get <path> -` writes to stdout.
    func downloadThumbnail(_ asset: PhotoAsset) -> Data? {
        guard let result = try? runner.run("\(binDir)/afcclient", arguments: ["get", asset.remotePath, "-"]),
              result.exitCode == 0, !result.stdout.isEmpty else {
            return nil
        }
        return result.stdout
    }

    func download(_ asset: PhotoAsset, to directory: URL) -> Bool {
        guard let data = downloadThumbnail(asset) else {
            return false
        }
        let destination = directory.appendingPathComponent(asset.filename)
        return (try? data.write(to: destination)) != nil
    }
}
