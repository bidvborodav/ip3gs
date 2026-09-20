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

    // ideviceinfo 1.4.0 (tools/ideviceinfo.c) reports "ERROR: Could not connect to lockdownd: <text> (<code>)".
    // -17 passcode locked, -18 pairing denied, -19 trust dialog pending, -21 host not known to device.
    private static let untrustedLockdownCodes: Set<Int> = [-17, -18, -19, -21]

    func checkConnection() -> DeviceState {
        guard let result = try? runner.run("\(binDir)/ideviceinfo", arguments: [], stdin: nil) else {
            return .notConnected
        }

        if result.exitCode != 0 {
            if let code = Self.lockdownErrorCode(in: result.stderr), Self.untrustedLockdownCodes.contains(code) {
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

    private static func lockdownErrorCode(in stderr: String) -> Int? {
        guard let line = stderr.split(separator: "\n").first(where: { $0.contains("Could not connect to lockdownd") }),
              let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"), open < close else {
            return nil
        }
        return Int(line[line.index(after: open)..<close])
    }

    private static let dcimPath = "/DCIM/100APPLE"

    func listPhotos(udid: String) -> [PhotoAsset] {
        guard let lines = runAFC(udid: udid, commands: ["ls \"\(Self.dcimPath)\""]),
              !lines.contains(where: { $0.hasPrefix("Error:") }) else {
            return []
        }

        return lines.map { filename in
            PhotoAsset(id: filename, filename: filename, remotePath: "\(Self.dcimPath)/\(filename)")
        }
    }

    // No real thumbnail exists on the device, so this is a full download read back from a temp dir.
    func downloadThumbnail(_ asset: PhotoAsset) -> Data? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard (try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        guard download(asset, to: tempDir) else {
            return nil
        }
        return try? Data(contentsOf: tempDir.appendingPathComponent(asset.filename))
    }

    // afcclient exits 0 even when `get` fails and only prints "Error: ...", so success is the file landing on disk.
    // [assumed] With no -u, afcclient targets the first connected device.
    func download(_ asset: PhotoAsset, to directory: URL) -> Bool {
        guard let lines = runAFC(udid: nil, commands: ["get -f \"\(asset.remotePath)\" \"\(directory.path)\""]),
              !lines.contains(where: { $0.hasPrefix("Error:") }) else {
            return false
        }
        let destination = directory.appendingPathComponent(asset.filename)
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0
    }

    // afcclient 1.4.0 ignores positional args: it reads commands from stdin and prints a colored
    // "afc:<dir> > " prompt (no newline) before each. It spins forever on EOF, so input must end with `quit`.
    private func runAFC(udid: String?, commands: [String]) -> [String]? {
        let arguments = udid.map { ["-u", $0] } ?? []
        let input = (commands + ["quit"]).joined(separator: "\n") + "\n"
        guard let result = try? runner.run("\(binDir)/afcclient", arguments: arguments, stdin: input),
              result.exitCode == 0 else {
            return nil
        }

        return String(decoding: result.stdout, as: UTF8.self)
            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            .replacingOccurrences(of: "afc:\\S* > ", with: "", options: .regularExpression)
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }
}
