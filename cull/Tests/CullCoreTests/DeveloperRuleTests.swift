import XCTest
@testable import CullCore

final class XcodeRuleTests: XCTestCase {
    private let derivedData = "Library/Developer/Xcode/DerivedData"

    func testStaleDerivedDataIsSelectedAndFreshIsNot() async throws {
        let fixture = try Fixture()
        let stale = "\(derivedData)/OldApp-abcdefghijklmnopqrstuvwxyzab"
        let fresh = "\(derivedData)/ThreadKeep-bcdefghijklmnopqrstuvwxyzabc"
        fixture.file("\(stale)/Build/Products/Debug/OldApp.app/OldApp", bytes: 40_000)
        fixture.plist("\(stale)/info.plist", ["WorkspacePath": fixture.path("Developer/OldApp/OldApp.xcodeproj")])
        fixture.file("\(fresh)/Build/Products/Debug/ThreadKeep.app/ThreadKeep", bytes: 20_000)
        fixture.file("\(fresh)/Index.noindex/DataStore/v5/units/x", fresh: true)
        fixture.file("\(derivedData)/ModuleCache.noindex/ABC/Foundation.pcm")

        let report = try await fixture.scan()
        let old = try XCTUnwrap(report.item("xcode.derivedData", titled: "OldApp"))
        XCTAssertTrue(old.selectedByDefault)
        XCTAssertEqual(old.action, .delete)
        XCTAssertEqual(old.paths, [fixture.path(stale)])
        XCTAssertEqual(old.subtitle, "~/Developer/OldApp/OldApp.xcodeproj")
        XCTAssertEqual(old.lastUsedLabel, "Last built")

        let active = try XCTUnwrap(report.item("xcode.derivedData", titled: "ThreadKeep"))
        XCTAssertFalse(active.selectedByDefault, "a project built yesterday keeps its build data")
        let lastBuilt = try XCTUnwrap(active.lastUsed)
        XCTAssertEqual(fixture.now.timeIntervalSince(lastBuilt) / 86_400, 1, accuracy: 0.01)

        XCTAssertEqual(report.item("xcode.derivedData", titled: "Shared module cache")?.selectedByDefault, true)
        XCTAssertEqual(report.category("xcode.derivedData")?.tier, .rebuildable)
        // Biggest first.
        XCTAssertEqual(report.items("xcode.derivedData").first?.title, "OldApp")
        XCTAssertEqual(report.skippedNotes, [])
    }

    func testStalenessThresholdIsConfigurable() async throws {
        let fixture = try Fixture()
        let project = "\(derivedData)/App-abcdefghijklmnopqrstuvwxyzab"
        fixture.file("\(project)/Build/x")
        fixture.touch("\(project)/Build/x", daysAgo: 10)

        var options = fixture.options()
        options.staleDays = 14
        var report = try await fixture.scan(options)
        XCTAssertEqual(report.item("xcode.derivedData", titled: "App")?.selectedByDefault, false)

        options.staleDays = 7
        report = try await fixture.scan(options)
        XCTAssertEqual(report.item("xcode.derivedData", titled: "App")?.selectedByDefault, true)
    }

    func testSharedBuildCachesWaitForXcodeToQuit() async throws {
        let fixture = try Fixture()
        fixture.file("\(derivedData)/ModuleCache.noindex/x")
        fixture.file("Library/Caches/com.apple.dt.Xcode/x")
        fixture.file("Library/Developer/Xcode/UserData/Previews/Simulator Devices/x")

        let report = try await fixture.scan(runningApps: ["com.apple.dt.Xcode"])
        for (category, title) in [("xcode.derivedData", "Shared module cache"), ("caches.xcode", "Xcode caches"),
                                  ("xcode.previews", "SwiftUI preview data")] {
            let item = try XCTUnwrap(report.item(category, titled: title))
            XCTAssertFalse(item.selectedByDefault)
            XCTAssertEqual(item.caution, "Xcode is running")
        }
    }

    func testProjectNamesLoseOnlyRealXcodeHashes() {
        XCTAssertEqual(Rule.derivedDataProjectName("My-App-abcdefghijklmnopqrstuvwxyzab"), "My-App")
        XCTAssertEqual(Rule.derivedDataProjectName("My-App"), "My-App")
        XCTAssertEqual(Rule.derivedDataProjectName("App-ABCDEFGHIJKLMNOPQRSTUVWXYZAB"), "App-ABCDEFGHIJKLMNOPQRSTUVWXYZAB")
        XCTAssertEqual(Rule.derivedDataProjectName("-abcdefghijklmnopqrstuvwxyzab"), "-abcdefghijklmnopqrstuvwxyzab")
    }

    func testKeepsTheNewestDeviceSupportPerPlatform() async throws {
        let fixture = try Fixture()
        let ios = "Library/Developer/Xcode/iOS DeviceSupport"
        fixture.file("\(ios)/iPhone15,2 17.5 (21F90)/Symbols/x")
        fixture.file("\(ios)/iPhone17,1 18.5 (22F76)/Symbols/x")
        fixture.file("\(ios)/iPhone18,1 26.1 (23B85)/Symbols/x")
        fixture.touch("\(ios)/iPhone15,2 17.5 (21F90)", daysAgo: 300)
        fixture.touch("\(ios)/iPhone17,1 18.5 (22F76)", daysAgo: 120)
        fixture.touch("\(ios)/iPhone18,1 26.1 (23B85)", daysAgo: 20)
        fixture.file("Library/Developer/Xcode/watchOS DeviceSupport/Watch7,1 11.5 (22T572)/Symbols/x")

        let report = try await fixture.scan()
        let items = Dictionary(uniqueKeysWithValues: report.items("xcode.deviceSupport").map { ($0.title, $0.selectedByDefault) })
        XCTAssertEqual(items, [
            "iOS iPhone15,2 17.5 (21F90)": true,
            "iOS iPhone17,1 18.5 (22F76)": true,
            "iOS iPhone18,1 26.1 (23B85)": false,
            "watchOS Watch7,1 11.5 (22T572)": false,
        ])
        XCTAssertEqual(report.skippedNotes, [])
    }

    func testArchivesAreReviewOnlyAndGoToTheTrash() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Developer/Xcode/Archives/2025-03-01/ThreadKeep 3-1-25, 9.41 AM.xcarchive/dSYMs/x")
        fixture.file("Library/Developer/Xcode/Archives/2025-03-01/notes.txt")

        let report = try await fixture.scan()
        let items = report.items("xcode.archives")
        XCTAssertEqual(items.map(\.title), ["ThreadKeep 3-1-25, 9.41 AM"])
        XCTAssertEqual(items.first?.action, .trash)
        XCTAssertEqual(items.first?.selectedByDefault, false)
        XCTAssertEqual(report.category("xcode.archives")?.tier, .review)
    }

    func testXcodeAndSimulatorCaches() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Caches/com.apple.dt.Xcode/Downloads/x")
        fixture.file("Library/Caches/com.apple.dt.xcodebuild/x")
        fixture.file("Library/Developer/CoreSimulator/Caches/dyld/x")
        fixture.file("Library/Developer/Xcode/DocumentationCache/v1/x")
        fixture.file("Library/Developer/XCTestDevices/ABC/data/x")

        let report = try await fixture.scan()
        let xcode = try XCTUnwrap(report.item("caches.xcode", titled: "Xcode caches"))
        XCTAssertEqual(Set(xcode.paths), [
            fixture.path("Library/Caches/com.apple.dt.Xcode"), fixture.path("Library/Caches/com.apple.dt.xcodebuild"),
        ])
        XCTAssertNotNil(report.item("caches.xcode", titled: "Simulator caches"))
        XCTAssertNotNil(report.item("caches.xcode", titled: "Documentation cache"))
        XCTAssertEqual(report.item("xcode.previews", titled: "Test simulators")?.selectedByDefault, true)
        XCTAssertEqual(report.skippedNotes, [])
    }
}

final class ProjectRuleTests: XCTestCase {
    private func artifacts(_ report: ScanReport) -> [String: CullItem] {
        Dictionary(uniqueKeysWithValues: report.items("projects.artifacts").map { ($0.title, $0) })
    }

    func testStaleLockedNodeModulesAreSelected() async throws {
        let fixture = try Fixture()
        fixture.file("Developer/old-site/package.json")
        fixture.file("Developer/old-site/package-lock.json")
        fixture.file("Developer/old-site/src/App.tsx")
        fixture.file("Developer/old-site/node_modules/react/index.js", bytes: 30_000)
        fixture.file("Developer/old-site/.next/cache/webpack/x")

        let items = artifacts(try await fixture.scan())
        let modules = try XCTUnwrap(items["old-site · node_modules"])
        XCTAssertTrue(modules.selectedByDefault)
        XCTAssertEqual(modules.action, .delete)
        XCTAssertEqual(modules.paths, [fixture.path("Developer/old-site/node_modules")])
        XCTAssertEqual(modules.subtitle, "~/Developer/old-site")
        XCTAssertEqual(modules.scope, .artifact(root: fixture.path("Developer"), names: ["node_modules"]))
        XCTAssertEqual(items["old-site · .next"]?.selectedByDefault, true)
    }

    func testRecentlyTouchedProjectsKeepEverything() async throws {
        let fixture = try Fixture()
        fixture.file("Developer/active/package.json")
        fixture.file("Developer/active/package-lock.json")
        fixture.file("Developer/active/node_modules/react/index.js")
        // Editing a file deep in the tree does not touch any folder above it.
        fixture.file("Developer/active/src/components/Button.tsx", fresh: true)

        let items = artifacts(try await fixture.scan())
        let modules = try XCTUnwrap(items["active · node_modules"])
        XCTAssertFalse(modules.selectedByDefault)
        let touched = try XCTUnwrap(modules.lastUsed)
        XCTAssertEqual(fixture.now.timeIntervalSince(touched) / 86_400, 1, accuracy: 0.01)
    }

    func testGitActivityCountsAsWork() async throws {
        let fixture = try Fixture()
        fixture.file("Developer/committed/package.json")
        fixture.file("Developer/committed/yarn.lock")
        fixture.file("Developer/committed/node_modules/x/index.js")
        fixture.file("Developer/committed/.git/HEAD")
        fixture.file("Developer/committed/.git/index", fresh: true)

        let items = artifacts(try await fixture.scan())
        XCTAssertEqual(items["committed · node_modules"]?.selectedByDefault, false)
    }

    func testAFreshInstallCountsAsWork() async throws {
        let fixture = try Fixture()
        fixture.file("Developer/reinstalled/package.json")
        fixture.file("Developer/reinstalled/package-lock.json")
        fixture.file("Developer/reinstalled/node_modules/x/index.js")
        fixture.touch("Developer/reinstalled/node_modules", daysAgo: 2)

        let items = artifacts(try await fixture.scan())
        XCTAssertEqual(items["reinstalled · node_modules"]?.selectedByDefault, false)
    }

    func testAProjectThatIsRunButNeverEditedKeepsItsDependencies() async throws {
        let fixture = try Fixture()
        // Nobody has edited this in over a year...
        fixture.file("Developer/dashboard/package.json")
        fixture.file("Developer/dashboard/package-lock.json")
        fixture.file("Developer/dashboard/src/server.js")
        fixture.file("Developer/dashboard/node_modules/express/index.js")
        fixture.file("Developer/dashboard/.next/server/app.js")
        // ...but the dev server wrote its caches yesterday, so it is clearly in use.
        fixture.file("Developer/dashboard/node_modules/.vite/deps/_metadata.json", fresh: true)
        fixture.file("Developer/dashboard/.next/cache/webpack/client.pack", fresh: true)

        let items = artifacts(try await fixture.scan())
        let modules = try XCTUnwrap(items["dashboard · node_modules"])
        XCTAssertFalse(modules.selectedByDefault)
        XCTAssertEqual(items["dashboard · .next"]?.selectedByDefault, false)
        let used = try XCTUnwrap(modules.lastUsed)
        XCTAssertEqual(fixture.now.timeIntervalSince(used) / 86_400, 1, accuracy: 0.01, "the date shown is the recent use")
    }

    func testWithoutALockfileNothingIsPreselected() async throws {
        let fixture = try Fixture()
        fixture.file("Developer/loose/package.json")
        fixture.file("Developer/loose/node_modules/x/index.js")

        let items = artifacts(try await fixture.scan())
        let modules = try XCTUnwrap(items["loose · node_modules"])
        XCTAssertFalse(modules.selectedByDefault)
        XCTAssertNotNil(modules.caution)
    }

    func testWorkspacePackagesInheritTheRootLockfile() async throws {
        let fixture = try Fixture()
        fixture.file("Developer/mono/package.json")
        fixture.file("Developer/mono/pnpm-lock.yaml")
        fixture.file("Developer/mono/node_modules/.pnpm/x/index.js")
        fixture.file("Developer/mono/packages/web/package.json")
        fixture.file("Developer/mono/packages/web/node_modules/y/index.js")
        fixture.file("Developer/mono/packages/web/.turbo/cache/x")

        let items = artifacts(try await fixture.scan())
        XCTAssertEqual(items["mono · node_modules"]?.selectedByDefault, true)
        XCTAssertEqual(items["web · node_modules"]?.selectedByDefault, true)
        XCTAssertEqual(items["web · .turbo"]?.selectedByDefault, true)
    }

    func testAFolderOnlyCountsWithItsManifestBesideIt() async throws {
        let fixture = try Fixture()
        // No package.json, Package.swift, Cargo.toml or pyvenv.cfg: these are just folders.
        fixture.file("Developer/notes/node_modules/readme.txt")
        fixture.file("Developer/notes/.build/output.bin")
        fixture.file("Developer/notes/target/report.pdf")
        fixture.file("Developer/notes/venv/photo.jpg")
        fixture.file("Developer/notes/Pods/list.txt")
        fixture.file("Developer/notes/DerivedData/thing")
        // Cargo.toml present, but `target` does not look like Cargo's.
        fixture.file("Developer/rusty/Cargo.toml")
        fixture.file("Developer/rusty/target/my-own-file.txt")

        let report = try await fixture.scan()
        XCTAssertNil(report.category("projects.artifacts"))
    }

    func testRecognisesEachEcosystem() async throws {
        let fixture = try Fixture()
        fixture.file("Developer/pkg/Package.swift")
        fixture.file("Developer/pkg/.build/debug/pkg")
        fixture.file("Developer/ios/Podfile")
        fixture.file("Developer/ios/Podfile.lock")
        fixture.file("Developer/ios/Pods/Alamofire/x.swift")
        fixture.file("Developer/ios/App.xcodeproj/project.pbxproj")
        fixture.file("Developer/ios/DerivedData/Build/x")
        fixture.file("Developer/crate/Cargo.toml")
        fixture.file("Developer/crate/target/debug/crate")
        fixture.file("Developer/py/uv.lock")
        fixture.file("Developer/py/.venv/pyvenv.cfg")
        fixture.file("Developer/py/.venv/lib/python3.13/site-packages/x.py")
        fixture.file("Developer/py2/venv/pyvenv.cfg")
        fixture.file("Developer/py2/venv/lib/x.py")
        fixture.file("Developer/py2/requirements.txt")

        let report = try await fixture.scan()
        let items = artifacts(report)
        XCTAssertEqual(Set(items.keys), [
            "pkg · .build", "ios · Pods", "ios · DerivedData", "crate · target", "py · .venv", "py2 · venv",
        ])
        XCTAssertEqual(items["py · .venv"]?.selectedByDefault, true)
        // A requirements.txt is not a lockfile: what was installed by hand would be lost.
        XCTAssertEqual(items["py2 · venv"]?.selectedByDefault, false)
        XCTAssertNotNil(items["py2 · venv"]?.caution)
        XCTAssertEqual(report.skippedNotes, [])
    }

    func testDoesNotLookInsideDependenciesOrBundles() async throws {
        let fixture = try Fixture()
        fixture.file("Developer/app/package.json")
        fixture.file("Developer/app/package-lock.json")
        fixture.file("Developer/app/node_modules/dep/package.json")
        fixture.file("Developer/app/node_modules/dep/node_modules/nested/index.js")
        fixture.file("Developer/Thing.app/Contents/Resources/package.json")
        fixture.file("Developer/Thing.app/Contents/Resources/node_modules/x/index.js")
        fixture.file("Developer/.hidden/package.json")
        fixture.file("Developer/.hidden/node_modules/x/index.js")

        let items = artifacts(try await fixture.scan())
        XCTAssertEqual(Set(items.keys), ["app · node_modules"])
    }

    func testCustomRootsReplaceTheDefaults() async throws {
        let fixture = try Fixture()
        for folder in ["Developer/a", "Elsewhere/b"] {
            fixture.file("\(folder)/package.json")
            fixture.file("\(folder)/package-lock.json")
            fixture.file("\(folder)/node_modules/x/index.js")
        }

        let report = try await fixture.scan(fixture.options(roots: ["~/Elsewhere/"]))
        XCTAssertEqual(Set(artifacts(report).keys), ["b · node_modules"])
    }

    func testRootsOutsideHomeOrBehindSymlinksAreIgnored() async throws {
        let fixture = try Fixture()
        let outside = fixture.base + "/outside"
        try FileManager.default.createDirectory(atPath: outside + "/proj/node_modules/x", withIntermediateDirectories: true)
        for (name, size) in [("package.json", 2), ("package-lock.json", 2), ("node_modules/x/index.js", 9_000)] {
            XCTAssertTrue(FileManager.default.createFile(
                atPath: outside + "/proj/" + name, contents: Data(repeating: 0x7B, count: size)
            ))
        }
        fixture.symlink("Developer", to: outside)

        let report = try await fixture.scan(fixture.options(roots: [outside, fixture.path("Developer"), fixture.home, "~"]))
        XCTAssertNil(report.category("projects.artifacts"))
        XCTAssertEqual(report.skippedNotes, [])
    }

    func testOverlappingRootsDoNotDoubleCount() async throws {
        let fixture = try Fixture()
        fixture.file("Documents/GitHub/site/package.json")
        fixture.file("Documents/GitHub/site/package-lock.json")
        fixture.file("Documents/GitHub/site/node_modules/x/index.js")

        let options = fixture.options(roots: ["~/Documents", "~/Documents/GitHub", "~/Documents/GitHub/site"])
        let report = try await fixture.scan(options)
        XCTAssertEqual(report.items("projects.artifacts").count, 1)
    }

    func testProjectsOnTheDesktopAndInDocumentsAreFoundByDefault() async throws {
        let fixture = try Fixture()
        for folder in ["Desktop/experiment", "Documents/GitHub/blog", "Sites/portfolio"] {
            fixture.file("\(folder)/package.json")
            fixture.file("\(folder)/package-lock.json")
            fixture.file("\(folder)/node_modules/x/index.js")
        }
        let items = artifacts(try await fixture.scan())
        XCTAssertEqual(Set(items.keys), ["experiment · node_modules", "blog · node_modules", "portfolio · node_modules"])
    }
}
