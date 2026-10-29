import Foundation

struct ShellResult: Sendable {
    var status: Int32
    var output: String
    var error: String
}

enum Shell {
    /// Runs a program and waits for it. Call from a background task.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, output: "", error: error.localizedDescription)
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(
            status: process.terminationStatus,
            output: String(decoding: outData, as: UTF8.self),
            error: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Starts a shell command without waiting for it.
    static func spawn(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    @discardableResult
    static func launchctl(_ arguments: String...) -> ShellResult {
        run("/bin/launchctl", arguments)
    }

    static var guiDomain: String { "gui/\(getuid())" }
}
