import XCTest
@testable import CullCore

final class UserFileRuleTests: XCTestCase {
    func testOldDownloadsAreListedForReview() async throws {
        let fixture = try Fixture()
        fixture.file("Downloads/tax-return-2024.pdf")
        fixture.file("Downloads/old-project/readme.md")
        fixture.file("Downloads/just-arrived.zip", fresh: true)
        fixture.file("Downloads/movie.mkv.crdownload")
        fixture.file("Downloads/Unconfirmed 1234.download")
        fixture.file("Downloads/.DS_Store")

        let report = try await fixture.scan()
        let items = report.items("downloads.old")
        XCTAssertEqual(Set(items.map(\.title)), ["tax-return-2024.pdf", "old-project"])
        XCTAssertTrue(items.allSatisfy { $0.action == .trash && !$0.selectedByDefault })
        XCTAssertEqual(report.category("downloads.old")?.tier, .review)
        XCTAssertEqual(report.skippedNotes, [])
    }

    func testInstallersAreFlaggedSooner() async throws {
        let fixture = try Fixture()
        fixture.file("Downloads/Xcode_26.xip")
        fixture.file("Downloads/App.dmg")
        fixture.file("Downloads/notes.txt")
        for name in ["Xcode_26.xip", "App.dmg", "notes.txt"] { fixture.touch("Downloads/\(name)", daysAgo: 30) }
        fixture.file("Downloads/Fresh.pkg")
        fixture.touch("Downloads/Fresh.pkg", daysAgo: 5)

        let report = try await fixture.scan()
        let items = report.items("downloads.old")
        XCTAssertEqual(Set(items.map(\.title)), ["Xcode_26.xip", "App.dmg"])
        XCTAssertTrue(items.allSatisfy { $0.subtitle == "Installer" })
    }

    func testTrashIsOneItemThatIsNeverPreselected() async throws {
        let fixture = try Fixture()
        fixture.file(".Trash/old-export.zip", bytes: 30_000)
        fixture.file(".Trash/Some Folder/inner/file.txt")
        fixture.file(".Trash/.DS_Store")
        fixture.symlink(".Trash/dangling-link", to: "/nowhere")

        let report = try await fixture.scan()
        let items = report.items("trash")
        XCTAssertEqual(items.count, 1)
        let trash = try XCTUnwrap(items.first)
        XCTAssertEqual(Set(trash.paths), [
            fixture.path(".Trash/old-export.zip"), fixture.path(".Trash/Some Folder"), fixture.path(".Trash/dangling-link"),
        ])
        XCTAssertEqual(trash.action, .delete)
        XCTAssertFalse(trash.selectedByDefault)
        XCTAssertEqual(trash.subtitle, "3 items")
        XCTAssertEqual(report.skippedNotes, [])
    }

    func testAnEmptyTrashIsNotListed() async throws {
        let fixture = try Fixture()
        fixture.dir(".Trash")
        fixture.file(".Trash/.DS_Store")
        let report = try await fixture.scan()
        XCTAssertNil(report.category("trash"))
    }

    func testDeviceBackupsShowTheDeviceName() async throws {
        let fixture = try Fixture()
        let backup = "Library/Application Support/MobileSync/Backup/00008110-001A2B3C4D5E"
        fixture.file("\(backup)/Manifest.db", bytes: 50_000)
        fixture.plist("\(backup)/Info.plist", [
            "Device Name": "Sam's iPhone", "Product Name": "iPhone 17 Pro",
            "Last Backup Date": fixture.now.addingTimeInterval(-200 * 86_400),
        ])
        fixture.file("Library/Application Support/MobileSync/Backup/unnamed-backup/Manifest.db")

        let report = try await fixture.scan()
        let named = try XCTUnwrap(report.item("ios.backups", titled: "Sam's iPhone"))
        XCTAssertEqual(named.subtitle, "iPhone 17 Pro")
        XCTAssertEqual(named.action, .trash)
        XCTAssertFalse(named.selectedByDefault)
        let backedUp = try XCTUnwrap(named.lastUsed)
        XCTAssertEqual(fixture.now.timeIntervalSince(backedUp) / 86_400, 200, accuracy: 0.01)
        XCTAssertNotNil(report.item("ios.backups", titled: "unnamed-backup"))
        XCTAssertEqual(report.skippedNotes, [])
    }

    func testFirmwareDownloadsAreSafe() async throws {
        let fixture = try Fixture()
        fixture.file("Library/iTunes/iPhone Software Updates/iPhone17,1_26.1_Restore.ipsw", bytes: 60_000)
        fixture.file("Library/iTunes/iTunes Library.itl")

        let report = try await fixture.scan()
        let item = try XCTUnwrap(report.item("ios.firmware", titled: "iPhone software updates"))
        XCTAssertTrue(item.selectedByDefault)
        XCTAssertEqual(item.paths, [fixture.path("Library/iTunes/iPhone Software Updates")])
    }

    // MARK: Exclusions and filters

    func testExcludedPathsAndItemsAreNeverOffered() async throws {
        let fixture = try Fixture()
        let derived = "Library/Developer/Xcode/DerivedData"
        fixture.file("\(derived)/Keep-abcdefghijklmnopqrstuvwxyzab/Build/x")
        fixture.file("\(derived)/Drop-bcdefghijklmnopqrstuvwxyzabc/Build/x")
        fixture.file(".npm/_cacache/x")
        fixture.file(".npm/_logs/x")
        fixture.file("Developer/vault/package.json")
        fixture.file("Developer/vault/package-lock.json")
        fixture.file("Developer/vault/node_modules/x/index.js")
        fixture.file("Library/Caches/Homebrew/x")

        let options = fixture.options(exclusions: [
            fixture.path("\(derived)/Keep-abcdefghijklmnopqrstuvwxyzab"),
            fixture.path(".npm/_logs"),
            fixture.path("Developer/vault"),
            "caches.packages|Homebrew downloads",
        ])
        let report = try await fixture.scan(options)
        XCTAssertEqual(report.items("xcode.derivedData").map(\.title), ["Drop"])
        XCTAssertEqual(report.item("caches.packages", titled: "npm")?.paths, [fixture.path(".npm/_cacache")])
        XCTAssertNil(report.category("projects.artifacts"), "excluding a folder covers everything inside it")
        XCTAssertNil(report.item("caches.packages", titled: "Homebrew downloads"))
    }

    func testNeverCullMatchesHoweverThePathIsSpelled() async throws {
        func survivors(_ exclusion: String) async throws -> [String] {
            let fixture = try Fixture()
            fixture.file("Developer/vault/package.json")
            fixture.file("Developer/vault/package-lock.json")
            fixture.file("Developer/vault/node_modules/x/index.js")
            fixture.dir("Developer/other")
            fixture.symlink("vault-link", to: fixture.path("Developer/vault"))
            let spelled = exclusion.replacingOccurrences(of: "HOME", with: fixture.home)
            let report = try await fixture.scan(fixture.options(exclusions: [spelled]))
            return report.items("projects.artifacts").map(\.title)
        }
        // Every one of these means the same folder and must protect it.
        for spelling in [
            "HOME/Developer/vault", "HOME/Developer/vault/", "HOME/Developer/vault///", "~/Developer/vault/",
            "HOME/Developer/./vault", "HOME/Developer/other/../vault", "HOME//Developer//vault",
            "HOME/vault-link", "HOME/DEVELOPER/Vault", "  HOME/Developer/vault  ",
            "HOME/Developer/vault/node_modules", "HOME/Developer",
        ] {
            let offered = try await survivors(spelling)
            XCTAssertEqual(offered, [], "\(spelling) should have excluded the project")
        }
        // And these must not exclude it (or anything else by accident).
        for spelling in ["HOME/Developer/vaul", "HOME/Developer/vault-old", "/", "HOME", "~", "HOME/Developer/gone/vault", ""] {
            let offered = try await survivors(spelling)
            XCTAssertEqual(offered, ["vault · node_modules"], "\(spelling) should not have excluded the project")
        }
    }

    func testScanCanBeLimitedToCategories() async throws {
        let fixture = try Fixture()
        fixture.file(".npm/_cacache/x")
        fixture.file("Library/Caches/com.some.app/x")
        fixture.file("Library/Caches/Homebrew/x")

        let report = try await fixture.scan(fixture.options(only: ["caches.apps"]))
        XCTAssertEqual(report.categories.map(\.id), ["caches.apps"])
        // Homebrew still belongs to the package rule even though that rule did not run.
        XCTAssertEqual(report.items("caches.apps").map(\.title), ["com.some.app"])
    }

    func testReportTotalsAndDefaultSelection() async throws {
        let fixture = try Fixture()
        fixture.file(".npm/_cacache/x", bytes: 100_000)
        fixture.file("Downloads/old.zip", bytes: 200_000)

        let report = try await fixture.scan()
        XCTAssertGreaterThanOrEqual(report.totalBytes, 300_000)
        XCTAssertGreaterThanOrEqual(report.defaultBytes, 100_000)
        XCTAssertLessThan(report.defaultBytes, 200_000)
        XCTAssertEqual(report.defaultSelection, ["caches.packages|npm"])
        XCTAssertEqual(report.bytes(selected: report.defaultSelection), report.defaultBytes)
        XCTAssertNotNil(report.disk)
        XCTAssertFalse(report.cancelled)
    }

    func testEveryRuleHasAUniqueIdentifier() {
        let identifiers = CullCatalog.entries.map(\.id)
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
        XCTAssertEqual(CullCatalog.entries.map(\.tier), CullCatalog.entries.map(\.tier).sorted(), "catalog is ordered by tier")
    }
}

final class SimulatorRuleTests: XCTestCase {
    private let gone = "11111111-1111-4111-8111-111111111111"
    private let used = "22222222-2222-4222-8222-222222222222"
    private let pristine = "33333333-3333-4333-8333-333333333333"
    private let booted = "44444444-4444-4444-8444-444444444444"
    private let oldRuntime = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    private let newRuntime = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"

    private func devicesJSON(_ fixture: Fixture) -> String {
        func device(_ udid: String, _ name: String, available: Bool, state: String = "Shutdown") -> String {
            """
            {"dataPath": "\(fixture.path("Library/Developer/CoreSimulator/Devices/\(udid)/data"))",
             "dataPathSize": 1, "logPath": "/x", "udid": "\(udid)", "isAvailable": \(available),
             "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17", "state": "\(state)",
             "lastBootedAt": "2026-01-15T10:00:00Z", "name": "\(name)"}
            """
        }
        return """
        {"devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [\(device(gone, "iPhone 15", available: false))],
          "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
            \(device(used, "iPhone 17 Pro", available: true)),
            \(device(pristine, "iPhone 17", available: true)),
            \(device(booted, "iPad Pro", available: true, state: "Booted"))]
        }}
        """
    }

    private var runtimesJSON: String {
        """
        {"\(oldRuntime)": {"build": "22F77", "deletable": true, "identifier": "\(oldRuntime)",
            "platformIdentifier": "com.apple.platform.iphonesimulator", "sizeBytes": 7607881728,
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-5", "state": "Ready",
            "lastUsedAt": "2026-02-01T09:00:00Z", "version": "18.5"},
         "\(newRuntime)": {"build": "23E244", "deletable": true, "identifier": "\(newRuntime)",
            "platformIdentifier": "com.apple.platform.iphonesimulator", "sizeBytes": 8200000000,
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-4", "state": "Ready", "version": "26.4"},
         "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC": {"build": "23N301", "deletable": false,
            "identifier": "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC", "sizeBytes": 9146991073, "state": "Ready",
            "platformIdentifier": "com.apple.platform.xrsimulator", "version": "26.2"},
         "not-a-uuid": {"identifier": "all", "sizeBytes": 1, "state": "Ready", "version": "1.0"}}
        """
    }

    private func makeFixture() throws -> (Fixture, FakeRunner) {
        let fixture = try Fixture()
        let devices = "Library/Developer/CoreSimulator/Devices"
        fixture.file("\(devices)/\(gone)/data/Library/x", bytes: 50_000)
        fixture.file("\(devices)/\(used)/data/Containers/Bundle/app", bytes: 400_000)
        fixture.file("\(devices)/\(pristine)/data/Library/x", bytes: 5_000)
        fixture.file("\(devices)/\(booted)/data/Containers/app", bytes: 400_000)
        let runner = FakeRunner()
        runner.respond(to: "simctl list devices -j", with: devicesJSON(fixture))
        runner.respond(to: "simctl runtime list -j", with: runtimesJSON)
        return (fixture, runner)
    }

    func testUnavailableSimulatorsAreDeletedThroughSimctl() async throws {
        let (fixture, runner) = try makeFixture()
        let report = try await fixture.scan(runner: runner)
        let items = report.items("sim.unavailable")
        XCTAssertEqual(items.map(\.title), ["iPhone 15 · iOS 17.5"])
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.action, .command(["/usr/bin/xcrun", "simctl", "delete", gone]))
        XCTAssertEqual(item.paths, [], "simulators are never removed by deleting their folders")
        XCTAssertTrue(item.selectedByDefault)
        XCTAssertGreaterThanOrEqual(item.bytes, 50_000)
        XCTAssertEqual(report.category("sim.unavailable")?.tier, .safe)
    }

    func testAnUnavailableSimulatorThatHoldsDataIsNotPreselected() async throws {
        let (fixture, runner) = try makeFixture()
        // The fixture's unavailable simulator holds 50 KB. Treat anything over 10 KB as lived-in.
        var options = fixture.options()
        options.livedInSimulatorBytes = 10_000
        let report = try await fixture.scan(options, runner: runner)
        let item = try XCTUnwrap(report.items("sim.unavailable").first)
        XCTAssertFalse(item.selectedByDefault, "its apps and data would come back with the runtime")
    }

    func testSimulatorContentsOfferEraseForLivedInShutDownDevices() async throws {
        let (fixture, runner) = try makeFixture()
        // The default floor is 200 MB. Nothing in the fixture is that large.
        var report = try await fixture.scan(runner: runner)
        XCTAssertNil(report.category("sim.data"))

        var options = fixture.options()
        options.livedInSimulatorBytes = 100_000
        report = try await fixture.scan(options, runner: runner)
        let items = report.items("sim.data")
        XCTAssertEqual(items.map(\.title), ["iPhone 17 Pro · iOS 26.4"], "not the pristine one, the booted one, or the unavailable one")
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.action, .command(["/usr/bin/xcrun", "simctl", "erase", used]))
        XCTAssertFalse(item.selectedByDefault)
        XCTAssertEqual(item.lastUsedLabel, "Last booted")
        XCTAssertNotNil(item.lastUsed)
        XCTAssertEqual(report.category("sim.data")?.tier, .review)
    }

    func testRuntimesAreListedWithTheirReportedSize() async throws {
        let (fixture, runner) = try makeFixture()
        let report = try await fixture.scan(runner: runner)
        let items = report.items("sim.runtimes")
        XCTAssertEqual(items.map(\.title), ["iOS 26.4 runtime", "iOS 18.5 runtime"], "largest first; undeletable and malformed entries dropped")
        let old = try XCTUnwrap(report.item("sim.runtimes", titled: "iOS 18.5 runtime"))
        XCTAssertEqual(old.bytes, 7_607_881_728)
        XCTAssertEqual(old.action, .command(["/usr/bin/xcrun", "simctl", "runtime", "delete", oldRuntime]))
        XCTAssertFalse(old.selectedByDefault)
        XCTAssertNil(old.caution)
        XCTAssertNotNil(old.lastUsed)
        let newest = try XCTUnwrap(report.item("sim.runtimes", titled: "iOS 26.4 runtime"))
        XCTAssertNotNil(newest.caution, "the newest runtime of a platform carries a warning")
        XCTAssertEqual(report.skippedNotes, [])
    }

    func testSimctlIsAskedOnlyOncePerListing() async throws {
        let (fixture, runner) = try makeFixture()
        _ = try await fixture.scan(runner: runner)
        let listings = runner.invocations.map { $0.dropFirst().joined(separator: " ") }.sorted()
        XCTAssertEqual(listings, ["simctl list devices -j", "simctl runtime list -j"])
    }

    func testNothingIsOfferedWithoutSimulatorTools() async throws {
        let (fixture, runner) = try makeFixture()
        var environment = try fixture.environment(runner: runner)
        environment.hasSimulatorTools = false
        let report = await Scanner(environment: environment, options: fixture.options()).scan()
        XCTAssertNil(report.category("sim.unavailable"))
        XCTAssertNil(report.category("sim.runtimes"))
        XCTAssertEqual(runner.invocations, [], "xcrun must not even be launched")
    }

    func testGarbageFromSimctlIsIgnored() async throws {
        let fixture = try Fixture()
        let runner = FakeRunner()
        runner.respond(to: "simctl list devices -j", with: "xcrun: error: unable to find utility \"simctl\"")
        runner.respond(to: "simctl runtime list -j", with: "{\"oops\": 3}", status: 1)
        let report = try await fixture.scan(runner: runner)
        XCTAssertEqual(report.categories.map(\.id), [])
    }

    func testRuntimeNames() {
        XCTAssertEqual(Simulators.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-26-4"), "iOS 26.4")
        XCTAssertEqual(Simulators.runtimeName("com.apple.CoreSimulator.SimRuntime.xrOS-26-2"), "visionOS 26.2")
        XCTAssertEqual(Simulators.runtimeName("com.apple.CoreSimulator.SimRuntime.watchOS-11-0-1"), "watchOS 11.0.1")
        XCTAssertTrue(Simulators.isNewer([26, 4], than: [18, 5]))
        XCTAssertTrue(Simulators.isNewer([26, 4, 1], than: [26, 4]))
        XCTAssertFalse(Simulators.isNewer([26, 4], than: [26, 4, 0]))
    }
}
