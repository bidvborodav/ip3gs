import Foundation

protocol ProcessRunning {
    func run(_ executablePath: String, arguments: [String], stdin: String?) throws -> (stdout: Data, stderr: String, exitCode: Int32)
}

struct SystemProcessRunner: ProcessRunning {
    func run(_ executablePath: String, arguments: [String], stdin: String?) throws -> (stdout: Data, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        try process.run()

        stdinPipe.fileHandleForWriting.write(Data((stdin ?? "").utf8))
        try? stdinPipe.fileHandleForWriting.close()

        // Drain both pipes before waiting: output past the pipe buffer would block the child forever.
        let stderrBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return (
            stdoutData,
            String(data: stderrBox.data, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
