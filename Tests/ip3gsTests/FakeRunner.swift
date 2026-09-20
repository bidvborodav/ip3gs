import Foundation
@testable import ip3gs

typealias RunResult = (stdout: Data, stderr: String, exitCode: Int32)

struct FakeRunner: ProcessRunning {
    let handler: (_ arguments: [String], _ stdin: String?) -> RunResult

    init(handler: @escaping (_ arguments: [String], _ stdin: String?) -> RunResult) {
        self.handler = handler
    }

    init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.init { _, _ in (Data(stdout.utf8), stderr, exitCode) }
    }

    func run(_ executablePath: String, arguments: [String], stdin: String?) throws -> RunResult {
        handler(arguments, stdin)
    }
}

final class Recorder {
    var arguments: [String] = []
    var stdin: String?
}

// Shaped after afcclient 1.4.0 (tools/afcclient.c): a colored "afc:<dir> > " prompt with no
// trailing newline before each command, then one colored name per line. Derived from source,
// not captured from a device.
func afcOutput(entries: [String]) -> String {
    let prompt = "\u{1B}[30m\u{1B}[47mafc:\u{1B}[0m\u{1B}[93m\u{1B}[44m/\u{1B}[0m > "
    let names = entries.map { "\u{1B}[0m\($0)\u{1B}[0m\n" }.joined()
    return prompt + names + prompt
}
