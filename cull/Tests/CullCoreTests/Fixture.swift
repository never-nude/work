import Foundation
import XCTest
@testable import CullCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A throwaway home folder.
///
/// The engine's clock (`now`) runs 400 days ahead of the real one. Anything a test creates is
/// therefore "old" unless the test marks it fresh, which works the same on Linux and macOS
/// (creation and date-added times cannot be backdated, but "now" can be moved forward).
final class Fixture {
    let base: String
    let home: String
    let now: Date

    init() throws {
        let temporary = NSTemporaryDirectory() + "cull-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: temporary + "/home", withIntermediateDirectories: true)
        base = try XCTUnwrap(Posix.realPath(temporary))
        home = base + "/home"
        now = Date().addingTimeInterval(400 * 86_400)
    }

    deinit {
        Posix.makeTreeWritable(base)
        try? FileManager.default.removeItem(atPath: base)
    }

    func path(_ relative: String) -> String {
        relative.isEmpty ? home : home + "/" + relative
    }

    @discardableResult
    func dir(_ relative: String) -> String {
        let full = path(relative)
        try! FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
        return full
    }

    /// Writes real bytes so the file occupies blocks on disk.
    @discardableResult
    func file(_ relative: String, bytes: Int = 8_192, fresh: Bool = false) -> String {
        let full = path(relative)
        try! FileManager.default.createDirectory(atPath: Posix.parent(of: full), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: full, contents: Data(repeating: 0x41, count: bytes)))
        if fresh { touch(relative, daysAgo: 1) }
        return full
    }

    /// Writes a small text file (for manifests whose contents matter).
    @discardableResult
    func text(_ relative: String, _ contents: String) -> String {
        let full = path(relative)
        try! FileManager.default.createDirectory(atPath: Posix.parent(of: full), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: full, contents: Data(contents.utf8)))
        return full
    }

    /// Sets the modification time relative to the fixture's clock.
    func touch(_ relative: String, daysAgo: Double) {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        try! FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path(relative))
    }

    func symlink(_ relative: String, to target: String) {
        let full = path(relative)
        try! FileManager.default.createDirectory(atPath: Posix.parent(of: full), withIntermediateDirectories: true)
        try! FileManager.default.createSymbolicLink(atPath: full, withDestinationPath: target)
    }

    func plist(_ relative: String, _ contents: [String: Any]) {
        let full = path(relative)
        try! FileManager.default.createDirectory(atPath: Posix.parent(of: full), withIntermediateDirectories: true)
        let data = try! PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
        XCTAssertTrue(FileManager.default.createFile(atPath: full, contents: data))
    }

    func exists(_ relative: String) -> Bool {
        Posix.info(at: path(relative)) != nil
    }

    func isEmptyDirectory(_ relative: String) -> Bool {
        Posix.entries(of: path(relative))?.isEmpty ?? false
    }

    func environment(
        runningApps: Set<String> = [], fullDiskAccess: Bool = true, runner: (any CommandRunning)? = nil
    ) throws -> CullEnvironment {
        let sandboxHome = home
        return try CullEnvironment(
            home: home, now: now, runningApps: runningApps, hasFullDiskAccess: fullDiskAccess,
            runner: runner, hasSimulatorTools: runner != nil,
            trash: { path in try CullEnvironment.sandboxTrash(path, home: sandboxHome) },
            isSandbox: true
        )
    }

    /// Options that list everything with any content, so tests do not need megabyte files.
    func options(
        roots: [String]? = nil, exclusions: [String] = [], only: Set<String>? = nil, minimum: Int64 = 1
    ) -> ScanOptions {
        ScanOptions(
            staleDays: 14, projectStaleDays: 30, downloadsAgeDays: 90, projectRoots: roots,
            exclusions: exclusions, onlyCategories: only, minimumItemBytes: minimum
        )
    }

    func scan(
        _ options: ScanOptions? = nil, runningApps: Set<String> = [], fullDiskAccess: Bool = true,
        runner: (any CommandRunning)? = nil
    ) async throws -> ScanReport {
        let environment = try environment(runningApps: runningApps, fullDiskAccess: fullDiskAccess, runner: runner)
        return await Scanner(environment: environment, options: options ?? self.options()).scan()
    }

    /// Every path under home, relative, files and folders alike.
    func snapshot() -> Set<String> {
        var all = Set<String>()
        var stack = [home]
        while let directory = stack.popLast() {
            for name in Posix.entries(of: directory) ?? [] {
                let full = Posix.join(directory, name)
                all.insert(String(full.dropFirst(home.count + 1)))
                if Posix.info(at: full)?.kind == .directory { stack.append(full) }
            }
        }
        return all
    }

    static var isRoot: Bool { geteuid() == 0 }
}

extension ScanReport {
    func category(_ id: String) -> CullCategory? {
        categories.first { $0.id == id }
    }

    func item(_ categoryID: String, titled title: String) -> CullItem? {
        category(categoryID)?.items.first { $0.title == title }
    }

    func items(_ categoryID: String) -> [CullItem] {
        category(categoryID)?.items ?? []
    }

    var skippedNotes: [String] { notes.filter { $0.hasPrefix("Skipped") } }
}

final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: CommandResult] = [:]
    private var recorded: [[String]] = []

    /// `command` is everything after the executable, e.g. "simctl list devices -j".
    func respond(to command: String, with output: String, status: Int32 = 0) {
        lock.lock()
        defer { lock.unlock() }
        responses[command] = CommandResult(status: status, output: output)
    }

    var invocations: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(_ arguments: [String], timeout: TimeInterval, captureErrors: Bool) -> CommandResult? {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(arguments)
        return responses[arguments.dropFirst().joined(separator: " ")] ?? CommandResult(status: 0, output: "")
    }
}
