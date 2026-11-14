import Foundation

public struct CommandResult: Sendable, Equatable {
    public var status: Int32
    public var output: String
    public var timedOut: Bool

    public init(status: Int32, output: String, timedOut: Bool = false) {
        self.status = status
        self.output = output
        self.timedOut = timedOut
    }

    public var succeeded: Bool { status == 0 && !timedOut }
}

/// Runs external tools. The only ones Cull ever asks for are `xcrun simctl …`.
public protocol CommandRunning: Sendable {
    /// Returns `nil` when the executable is missing or cannot be launched.
    /// `captureErrors` folds stderr into the output; leave it off when the output is parsed.
    func run(_ arguments: [String], timeout: TimeInterval, captureErrors: Bool) -> CommandResult?
}

public struct ProcessRunner: CommandRunning {
    public init() {}

    public func run(_ arguments: [String], timeout: TimeInterval, captureErrors: Bool) -> CommandResult? {
        guard let executable = arguments.first,
              FileManager.default.isExecutableFile(atPath: executable) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = captureErrors ? pipe : FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // A hung CoreSimulator service must not hang the scan.
        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // Drain before waiting, or a chatty child blocks on a full pipe.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        let timedOut = process.terminationReason == .uncaughtSignal
        return CommandResult(
            status: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self),
            timedOut: timedOut
        )
    }
}
