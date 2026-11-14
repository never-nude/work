import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum EnvironmentError: Error, CustomStringConvertible, Equatable {
    case unusableHome(String)

    public var description: String {
        switch self {
        case .unusableHome(let why): return "Cull can't work with this home folder: \(why)"
        }
    }
}

/// Everything the engine needs to know about the machine it runs on.
/// Tests build one around a throwaway directory.
public struct CullEnvironment: Sendable {
    /// Canonical absolute path of the home folder. Nothing outside it is ever deleted.
    public let home: String
    public var now: Date
    /// Lowercased bundle identifiers and app names of running apps.
    public var runningApps: Set<String>
    public var hasFullDiskAccess: Bool
    /// `nil` disables every rule that shells out.
    public var runner: (any CommandRunning)?
    /// True when a full Xcode with `simctl` is installed. Without it `xcrun` would pop up
    /// the "install developer tools" dialog, so simulator rules stay off.
    public var hasSimulatorTools: Bool
    /// Moves one path to the Trash. `nil` means trashing is unavailable.
    public var trash: (@Sendable (String) throws -> Void)?
    /// True when `home` is not the real home folder (tests, `CULL_HOME`).
    public let isSandbox: Bool

    /// Environment variable that points Cull at a stand-in home folder.
    public static let homeOverrideVariable = "CULL_HOME"

    /// Sandbox only: how many days ahead of the real clock Cull should believe it is.
    public static let clockOffsetVariable = "CULL_DAYS_AHEAD"

    /// Cull never deletes as root; the CLI and the app both check this up front.
    public static var isRunningAsRoot: Bool { Posix.isRoot }

    public init(
        home rawHome: String, now: Date = Date(), runningApps: Set<String> = [],
        hasFullDiskAccess: Bool = true, runner: (any CommandRunning)? = nil,
        hasSimulatorTools: Bool = false,
        trash: (@Sendable (String) throws -> Void)? = nil, isSandbox: Bool = true
    ) throws {
        guard rawHome.hasPrefix("/") else { throw EnvironmentError.unusableHome("\(rawHome) is not an absolute path") }
        guard let canonical = Posix.realPath(rawHome) else {
            throw EnvironmentError.unusableHome("\(rawHome) does not exist")
        }
        guard let folder = Posix.info(at: canonical), folder.kind == .directory else {
            throw EnvironmentError.unusableHome("\(canonical) is not a folder")
        }
        // "/", "/Users" and friends are never a home folder.
        let components = canonical.split(separator: "/")
        guard components.count >= 2 else {
            throw EnvironmentError.unusableHome("\(canonical) is too close to the top of the disk")
        }
        // A home folder belongs to whoever is running Cull. This is what rules out /tmp,
        // /Library, /usr/local and every other shared or system location, however deep.
        guard folder.ownerID == Posix.effectiveUserID else {
            throw EnvironmentError.unusableHome("\(canonical) does not belong to you")
        }
        self.home = canonical
        self.now = now
        self.runningApps = Set(runningApps.map { $0.lowercased() })
        self.hasFullDiskAccess = hasFullDiskAccess
        self.runner = runner
        self.hasSimulatorTools = hasSimulatorTools
        self.trash = trash
        self.isSandbox = isSandbox
    }

    /// The real machine, or a sandbox home when `CULL_HOME` (or `overrideHome`) is set.
    public static func live(overrideHome: String? = nil) throws -> CullEnvironment {
        let override = overrideHome ?? ProcessInfo.processInfo.environment[homeOverrideVariable]
        if let override, !override.isEmpty {
            var environment = try CullEnvironment(home: override, isSandbox: true)
            // A sandbox can pretend time has passed, so a freshly built stand-in home has stale things in it.
            if let days = ProcessInfo.processInfo.environment[clockOffsetVariable].flatMap(Double.init) {
                environment.now = Date().addingTimeInterval(days * 86_400)
            }
            let sandboxHome = environment.home
            environment.trash = { path in try sandboxTrash(path, home: sandboxHome) }
            return environment
        }
        var environment = try CullEnvironment(home: NSHomeDirectory(), isSandbox: false)
        environment.runningApps = currentlyRunningApps()
        environment.hasFullDiskAccess = probeFullDiskAccess(home: environment.home)
        environment.runner = ProcessRunner()
        environment.hasSimulatorTools = simulatorToolsInstalled()
        #if os(macOS)
        environment.trash = { path in
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        }
        #endif
        return environment
    }

    /// Stand-in for the Trash inside a sandbox home: move into `<home>/.Trash` under a free name.
    static func sandboxTrash(_ path: String, home: String) throws {
        let trashDirectory = Posix.join(home, ".Trash")
        try FileManager.default.createDirectory(atPath: trashDirectory, withIntermediateDirectories: true)
        let name = Posix.lastComponent(of: path)
        var destination = Posix.join(trashDirectory, name)
        var attempt = 1
        while Posix.info(at: destination) != nil {
            attempt += 1
            destination = Posix.join(trashDirectory, "\(name) \(attempt)")
        }
        try FileManager.default.moveItem(atPath: path, toPath: destination)
    }

    /// Looks for `simctl` in the selected developer directory without invoking `xcrun`.
    static func simulatorToolsInstalled() -> Bool {
        #if os(macOS)
        var candidates: [String] = []
        if let selected = Posix.realPath("/var/db/xcode_select_link") { candidates.append(selected) }
        candidates.append("/Applications/Xcode.app/Contents/Developer")
        return candidates.contains { FileManager.default.isExecutableFile(atPath: $0 + "/usr/bin/simctl") }
        #else
        return false
        #endif
    }

    static func currentlyRunningApps() -> Set<String> {
        var names = Set<String>()
        #if canImport(AppKit)
        for app in NSWorkspace.shared.runningApplications {
            if let identifier = app.bundleIdentifier { names.insert(identifier.lowercased()) }
            if let name = app.localizedName { names.insert(name.lowercased()) }
        }
        #endif
        return names
    }

    /// Full Disk Access has no API. The accepted probe is whether a TCC-protected file opens.
    static func probeFullDiskAccess(home: String) -> Bool {
        #if os(macOS)
        let probes = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        for probe in probes {
            let descriptor = open(probe, O_RDONLY)
            if descriptor >= 0 {
                close(descriptor)
                return true
            }
            if errno == EPERM || errno == EACCES { return false }
        }
        return Posix.entries(of: home + "/.Trash") != nil
        #else
        return true
        #endif
    }

    /// The name of a running app matching any of `identifiers` (bundle IDs or app names), if one is running.
    public func runningApp(matching identifiers: [String]) -> String? {
        for identifier in identifiers {
            let wanted = identifier.lowercased()
            guard !wanted.isEmpty else { continue }
            for running in runningApps {
                // com.foo.app also matches com.foo.app.helper, and the other way round.
                if running == wanted || running.hasPrefix(wanted + ".") || wanted.hasPrefix(running + ".") {
                    return identifier
                }
            }
        }
        return nil
    }
}
