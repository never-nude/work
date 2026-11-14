import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

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

        // A hung CoreSimulator service must not hang the scan: ask politely at the deadline,
        // then insist a few seconds later.
        let timedOut = Flag()
        let identifier = process.processIdentifier
        let watchdog = DispatchWorkItem { [process] in
            guard process.isRunning else { return }
            timedOut.raise()
            process.terminate()
        }
        let enforcer = DispatchWorkItem { [process] in
            if process.isRunning { _ = kill(identifier, SIGKILL) }
        }
        let queue = DispatchQueue.global(qos: .utility)
        queue.asyncAfter(deadline: .now() + timeout, execute: watchdog)
        queue.asyncAfter(deadline: .now() + timeout + 5, execute: enforcer)

        // Drain before waiting, or a chatty child blocks on a full pipe.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        enforcer.cancel()

        return CommandResult(
            status: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self),
            timedOut: timedOut.isRaised
        )
    }
}

/// A one-way flag that is safe to set from the watchdog and read from the caller.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    func raise() {
        lock.lock()
        raised = true
        lock.unlock()
    }

    var isRaised: Bool {
        lock.lock()
        defer { lock.unlock() }
        return raised
    }
}
