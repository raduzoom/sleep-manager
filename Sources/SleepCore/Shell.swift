import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String

    public var succeeded: Bool { status == 0 }
}

public enum Shell {
    /// Runs a command and waits for it. `output` holds stdout and stderr combined.
    @discardableResult
    public static func run(_ path: String, _ arguments: [String] = []) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
