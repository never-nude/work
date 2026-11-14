import Foundation

// Simulators are managed by CoreSimulator, so Cull asks `simctl` to remove them
// instead of deleting their folders out from under it.

struct SimulatorDevice: Decodable, Sendable {
    let udid: String
    let name: String?
    let state: String?
    let isAvailable: Bool?
    let dataPath: String?
    let availabilityError: String?
    let lastBootedAt: String?
}

struct SimulatorDeviceList: Decodable, Sendable {
    let devices: [String: [SimulatorDevice]]
}

struct SimulatorRuntime: Decodable, Sendable {
    let identifier: String?
    let version: String?
    let build: String?
    let sizeBytes: Int64?
    let state: String?
    let deletable: Bool?
    let platformIdentifier: String?
    let runtimeIdentifier: String?
    let lastUsedAt: String?
}

enum Simulators {
    static let xcrun = "/usr/bin/xcrun"

    struct ListedDevice: Sendable {
        let runtime: String
        let device: SimulatorDevice
    }

    static func parseDevices(_ json: String) -> [ListedDevice] {
        guard let list = try? JSONDecoder().decode(SimulatorDeviceList.self, from: Data(json.utf8)) else { return [] }
        return list.devices.keys.sorted().flatMap { runtime in
            (list.devices[runtime] ?? []).map { ListedDevice(runtime: runtime, device: $0) }
        }
    }

    static func parseRuntimes(_ json: String) -> [SimulatorRuntime] {
        guard let runtimes = try? JSONDecoder().decode([String: SimulatorRuntime].self, from: Data(json.utf8)) else {
            return []
        }
        return runtimes.keys.sorted().compactMap { runtimes[$0] }
    }

    static func devices(_ context: RuleContext) -> [ListedDevice] {
        context.memo.value("simulators.devices") {
            guard context.env.hasSimulatorTools, let runner = context.env.runner,
                  let result = runner.run([xcrun, "simctl", "list", "devices", "-j"], timeout: 45, captureErrors: false),
                  result.succeeded else { return [] }
            return parseDevices(result.output)
        }
    }

    static func runtimes(_ context: RuleContext) -> [SimulatorRuntime] {
        context.memo.value("simulators.runtimes") {
            guard context.env.hasSimulatorTools, let runner = context.env.runner,
                  let result = runner.run([xcrun, "simctl", "runtime", "list", "-j"], timeout: 45, captureErrors: false),
                  result.succeeded else { return [] }
            return parseRuntimes(result.output)
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-4" → "iOS 26.4".
    static func runtimeName(_ identifier: String) -> String {
        let tail = identifier.split(separator: ".").last.map(String.init) ?? identifier
        let pieces = tail.split(separator: "-").map(String.init)
        guard let platform = pieces.first, pieces.count > 1 else { return tail }
        let pretty = platform == "xrOS" ? "visionOS" : platform
        return pretty + " " + pieces.dropFirst().joined(separator: ".")
    }

    static func platformName(_ runtime: SimulatorRuntime) -> String {
        switch runtime.platformIdentifier ?? "" {
        case "com.apple.platform.iphonesimulator": return "iOS"
        case "com.apple.platform.watchsimulator": return "watchOS"
        case "com.apple.platform.appletvsimulator": return "tvOS"
        case "com.apple.platform.xrsimulator": return "visionOS"
        default:
            let name = runtimeName(runtime.runtimeIdentifier ?? "")
            return name.split(separator: " ").first.map(String.init) ?? "Simulator"
        }
    }

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    static func versionKey(_ version: String?) -> [Int] {
        (version ?? "").split(separator: ".").map { Int($0) ?? 0 }
    }

    static func isNewer(_ lhs: [Int], than rhs: [Int]) -> Bool {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// The device's folder, but only when it is where simulators are supposed to live.
    static func deviceDirectory(_ device: SimulatorDevice, context: RuleContext) -> String? {
        guard UUID(uuidString: device.udid) != nil,
              let devices = context.directory("Library/Developer/CoreSimulator/Devices") else { return nil }
        return context.directory(atPath: Posix.join(devices, device.udid))
    }
}

extension Rule {
    static let unavailableSimulators = Rule(
        id: "sim.unavailable",
        title: "Unavailable simulators",
        blurb: "Simulators whose OS runtime is not installed, so they cannot boot. Empty ones are pre-selected; ones holding app data are left for you to decide.",
        tier: .safe,
        symbol: "iphone.slash",
        detect: { context in
            Simulators.devices(context).compactMap { listed in
                let device = listed.device
                guard device.isAvailable == false, UUID(uuidString: device.udid) != nil else { return nil }
                let folder = Simulators.deviceDirectory(device, context: context)
                // Its runtime can come back (an Xcode update, a different Xcode selected), and the
                // apps and data inside come back with it. Only an empty shell is a throwaway.
                return Candidate(
                    key: device.udid,
                    title: "\(device.name ?? "Simulator") · \(Simulators.runtimeName(listed.runtime))",
                    subtitle: "Runtime not installed; holds data if it is large",
                    action: .command([Simulators.xcrun, "simctl", "delete", device.udid]),
                    policy: .smallerThan(context.options.livedInSimulatorBytes),
                    measuredPaths: folder.map { [$0] } ?? [],
                    minimumBytes: 0
                )
            }
        }
    )

    static let simulatorData = Rule(
        id: "sim.data",
        title: "Simulator contents",
        blurb: "Apps and data inside each simulator. Erasing resets a simulator to factory state; the simulator itself stays.",
        tier: .review,
        symbol: "apps.iphone",
        detect: { context in
            Simulators.devices(context).compactMap { listed in
                let device = listed.device
                guard device.isAvailable != false, device.state == "Shutdown",
                      let folder = Simulators.deviceDirectory(device, context: context) else { return nil }
                let data = Posix.join(folder, "data")
                guard context.isDirectory(data) else { return nil }
                return Candidate(
                    key: device.udid,
                    title: "\(device.name ?? "Simulator") · \(Simulators.runtimeName(listed.runtime))",
                    subtitle: "Erase all content and settings",
                    action: .command([Simulators.xcrun, "simctl", "erase", device.udid]),
                    policy: .never,
                    lastUsed: Simulators.date(device.lastBootedAt),
                    lastUsedLabel: "Last booted",
                    measuredPaths: [data],
                    // Only list simulators that have been lived in.
                    minimumBytes: context.options.livedInSimulatorBytes
                )
            }
        }
    )

    static let simulatorRuntimes = Rule(
        id: "sim.runtimes",
        title: "Simulator runtimes",
        blurb: "Whole simulator operating systems, several gigabytes each. Delete the versions you no longer test against; Xcode can download them again.",
        tier: .review,
        symbol: "opticaldisc",
        detect: { context in
            let runtimes = Simulators.runtimes(context).filter {
                $0.deletable != false && ($0.state ?? "Ready") == "Ready"
                    && $0.identifier.flatMap(UUID.init(uuidString:)) != nil
            }
            // Mark the newest of each platform: the current Xcode almost certainly wants it.
            var newest: [String: [Int]] = [:]
            for runtime in runtimes {
                let platform = Simulators.platformName(runtime)
                let version = Simulators.versionKey(runtime.version)
                if newest[platform].map({ Simulators.isNewer(version, than: $0) }) ?? true { newest[platform] = version }
            }
            return runtimes.compactMap { runtime in
                guard let identifier = runtime.identifier else { return nil }
                let platform = Simulators.platformName(runtime)
                let isNewest = newest[platform] == Simulators.versionKey(runtime.version)
                return Candidate(
                    key: identifier,
                    title: "\(platform) \(runtime.version ?? "") runtime",
                    subtitle: runtime.build.map { "Build \($0)" },
                    action: .command([Simulators.xcrun, "simctl", "runtime", "delete", identifier]),
                    policy: .never,
                    caution: isNewest ? "Newest \(platform) runtime; your Xcode probably needs it" : nil,
                    lastUsed: Simulators.date(runtime.lastUsedAt),
                    lastUsedLabel: "Last used",
                    fixedBytes: runtime.sizeBytes ?? 0,
                    minimumBytes: 0
                )
            }
        }
    )
}
