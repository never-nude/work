import XCTest
@testable import CullCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class CullerTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(Fixture.isRoot, "Cull refuses to delete as root, so these cannot run as root")
    }

    private func item(
        _ fixture: Fixture, _ relative: [String], action: ItemAction, scope: PathScope, bytes: Int64 = 8_192
    ) -> CullItem {
        CullItem(
            id: "test|" + relative.joined(separator: ","), categoryID: "test", title: relative.first ?? "item",
            paths: relative.map(fixture.path), action: action, scope: scope, bytes: bytes, selectedByDefault: true
        )
    }

    private func cull(_ fixture: Fixture, _ items: [CullItem], runner: FakeRunner? = nil) async throws -> CullSummary {
        await Culler(environment: try fixture.environment(runner: runner)).cull(items)
    }

    // MARK: The three file actions

    func testDeleteContentsEmptiesTheFolderButKeepsIt() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Caches/com.some.app/a")
        fixture.file("Library/Caches/com.some.app/deep/er/b")
        fixture.symlink("Library/Caches/com.some.app/link", to: fixture.dir("Documents"))
        fixture.file("Documents/keep.txt")

        let target = item(fixture, ["Library/Caches/com.some.app"], action: .deleteContents, scope: .under([fixture.path("Library/Caches")]))
        let summary = try await cull(fixture, [target])

        XCTAssertEqual(summary.outcomes.map(\.status), [.removed])
        XCTAssertTrue(fixture.isEmptyDirectory("Library/Caches/com.some.app"))
        XCTAssertTrue(fixture.exists("Documents/keep.txt"), "a symlink inside is unlinked, never followed")
        XCTAssertEqual(summary.deletedBytes, 8_192)
        XCTAssertEqual(summary.problems, [])
    }

    func testDeleteRemovesTheItemItself() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab/Build/x")
        fixture.file("Library/Developer/Xcode/DerivedData/Other-bcdefghijklmnopqrstuvwxyzabc/Build/x")

        let target = item(
            fixture, ["Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab"],
            action: .delete, scope: .under([fixture.path("Library/Developer/Xcode/DerivedData")])
        )
        let summary = try await cull(fixture, [target])

        XCTAssertEqual(summary.outcomes.map(\.status), [.removed])
        XCTAssertFalse(fixture.exists("Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab"))
        XCTAssertTrue(fixture.exists("Library/Developer/Xcode/DerivedData/Other-bcdefghijklmnopqrstuvwxyzabc/Build/x"))
    }

    func testTrashMovesInsteadOfDeleting() async throws {
        let fixture = try Fixture()
        fixture.file("Downloads/old.zip")
        fixture.file(".Trash/old.zip")  // a name clash must not overwrite what is already there

        let target = item(fixture, ["Downloads/old.zip"], action: .trash, scope: .under([fixture.path("Downloads")]))
        let summary = try await cull(fixture, [target])

        XCTAssertEqual(summary.outcomes.map(\.status), [.trashed])
        XCTAssertEqual(summary.trashedBytes, 8_192)
        XCTAssertEqual(summary.deletedBytes, 0)
        XCTAssertFalse(fixture.exists("Downloads/old.zip"))
        XCTAssertTrue(fixture.exists(".Trash/old.zip"))
        XCTAssertTrue(fixture.exists(".Trash/old.zip 2"))
    }

    func testTrashFailsCleanlyWhenThereIsNoTrash() async throws {
        let fixture = try Fixture()
        fixture.file("Downloads/old.zip")
        var environment = try fixture.environment()
        environment.trash = nil
        let target = item(fixture, ["Downloads/old.zip"], action: .trash, scope: .under([fixture.path("Downloads")]))
        let summary = await Culler(environment: environment).cull([target])

        XCTAssertEqual(summary.outcomes.map(\.status), [.failed])
        XCTAssertTrue(fixture.exists("Downloads/old.zip"))
    }

    func testThingsAlreadyGoneAreSkippedNotFailed() async throws {
        let fixture = try Fixture()
        fixture.dir("Library/Caches")
        let target = item(fixture, ["Library/Caches/com.vanished.app"], action: .deleteContents, scope: .under([fixture.path("Library/Caches")]))
        let summary = try await cull(fixture, [target])
        XCTAssertEqual(summary.outcomes.map(\.status), [.skipped])
        XCTAssertEqual(summary.deletedBytes, 0)
    }

    func testReadOnlyTreesAreRemoved() async throws {
        try XCTSkipIf(Fixture.isRoot, "root ignores permissions")
        let fixture = try Fixture()
        fixture.file("Library/Caches/go-build/aa/readonly.a")
        XCTAssertEqual(chmod(fixture.path("Library/Caches/go-build/aa/readonly.a"), 0o444), 0)
        XCTAssertEqual(chmod(fixture.path("Library/Caches/go-build/aa"), 0o555), 0)

        let target = item(fixture, ["Library/Caches/go-build"], action: .deleteContents, scope: .under([fixture.path("Library/Caches")]))
        let summary = try await cull(fixture, [target])
        XCTAssertEqual(summary.outcomes.map(\.status), [.removed])
        XCTAssertTrue(fixture.isEmptyDirectory("Library/Caches/go-build"))
    }

    func testWhatCannotBeRemovedIsReportedHonestly() async throws {
        try XCTSkipIf(Fixture.isRoot, "root ignores permissions")
        let fixture = try Fixture()
        fixture.file("Library/Caches/com.locked.app/stuck", bytes: 20_000)
        // The folder being emptied is itself read-only, so its entries cannot be unlinked.
        XCTAssertEqual(chmod(fixture.path("Library/Caches/com.locked.app"), 0o555), 0)

        let target = item(fixture, ["Library/Caches/com.locked.app"], action: .deleteContents, scope: .under([fixture.path("Library/Caches")]), bytes: 20_480)
        let summary = try await cull(fixture, [target])
        XCTAssertEqual(summary.outcomes.map(\.status), [.failed])
        XCTAssertEqual(summary.deletedBytes, 0)
        XCTAssertEqual(summary.problems.count, 1)
        XCTAssertNotNil(summary.outcomes.first?.message)
        XCTAssertTrue(fixture.exists("Library/Caches/com.locked.app/stuck"))
    }

    func testPartialRemovalReportsOnlyWhatWent() async throws {
        try XCTSkipIf(Fixture.isRoot, "root ignores permissions")
        let fixture = try Fixture()
        fixture.file("Library/Caches/one.free.app/x", bytes: 40_000)
        fixture.file("Library/Caches/two.stuck.app/x", bytes: 40_000)
        XCTAssertEqual(chmod(fixture.path("Library/Caches/two.stuck.app"), 0o555), 0)

        let target = item(
            fixture, ["Library/Caches/one.free.app", "Library/Caches/two.stuck.app"],
            action: .deleteContents, scope: .under([fixture.path("Library/Caches")]), bytes: 81_920
        )
        let summary = try await cull(fixture, [target])
        XCTAssertEqual(summary.outcomes.map(\.status), [.partial])
        XCTAssertGreaterThan(summary.deletedBytes, 30_000)
        XCTAssertLessThan(summary.deletedBytes, 50_000)
    }

    // MARK: The guard is consulted again at deletion time

    func testATamperedItemIsRefused() async throws {
        let fixture = try Fixture()
        fixture.file("Documents/thesis.docx")
        fixture.file("Desktop/shot.png")
        fixture.file(".ssh/id_ed25519")
        fixture.file("Library/Messages/chat.db")
        fixture.file("Developer/app/src/main.swift")
        fixture.file("Downloads/keep.zip")

        // Each of these pairs a precious path with the most permissive scope that could be forged for it.
        let attempts = [
            item(fixture, ["Documents/thesis.docx"], action: .delete, scope: .under([fixture.path("Documents")])),
            item(fixture, ["Documents/thesis.docx"], action: .trash, scope: .under([fixture.path("Documents")])),
            item(fixture, ["Documents"], action: .deleteContents, scope: .under([fixture.home])),
            item(fixture, ["Desktop/shot.png"], action: .delete, scope: .under([fixture.path("Desktop")])),
            item(fixture, [".ssh/id_ed25519"], action: .delete, scope: .under([fixture.path(".ssh")])),
            item(fixture, ["Library/Messages"], action: .deleteContents, scope: .under([fixture.path("Library")])),
            item(fixture, ["Library/Messages/chat.db"], action: .trash, scope: .under([fixture.path("Library/Messages")])),
            item(fixture, ["Library/Caches/../Messages/chat.db"], action: .delete, scope: .under([fixture.path("Library/Caches")])),
            item(fixture, ["Developer/app/src"], action: .delete, scope: .artifact(root: fixture.path("Developer"), names: ["src"])),
            item(fixture, ["Developer/app/src"], action: .delete, scope: .under([fixture.path("Developer/app")])),
            item(fixture, ["Downloads/keep.zip"], action: .delete, scope: .under([fixture.path("Downloads")])),
        ]
        let before = fixture.snapshot()
        let summary = try await cull(fixture, attempts)

        XCTAssertTrue(summary.outcomes.allSatisfy { $0.status == .failed })
        XCTAssertTrue(summary.outcomes.allSatisfy { $0.message?.contains("Refused") ?? false })
        XCTAssertEqual(fixture.snapshot(), before, "nothing may change")
    }

    func testBuildArtifactsNeedTheirManifestAtDeletionTimeToo() async throws {
        let fixture = try Fixture()
        // Folders with artifact names, but nothing beside them that says what they are.
        fixture.file("Documents/Research/target/findings.pdf")
        fixture.file("Documents/Recipes/node_modules/grandmas-notes.txt")
        fixture.file("Developer/app/venv/not-really-an-environment.txt")
        fixture.file("Developer/tool/.build/output")
        // A file, not a folder, where an artifact was expected.
        fixture.file("Developer/site/package.json")
        fixture.file("Developer/site/node_modules")
        // And the real thing, which must still go.
        fixture.file("Developer/real/package.json")
        fixture.file("Developer/real/node_modules/react/index.js")
        fixture.file("Developer/pkg/Package.swift")
        fixture.file("Developer/pkg/.build/debug/pkg")
        fixture.file("Developer/py/.venv/pyvenv.cfg")
        fixture.file("Developer/ios/App.xcodeproj/project.pbxproj")
        fixture.file("Developer/ios/DerivedData/Build/x")

        func artifact(_ relative: String) -> CullItem {
            let root = fixture.path(String(relative.split(separator: "/")[0]))
            let name = Posix.lastComponent(of: relative)
            return item(fixture, [relative], action: .delete, scope: .artifact(root: root, names: [name]))
        }
        let forged = ["Documents/Research/target", "Documents/Recipes/node_modules", "Developer/app/venv",
                      "Developer/tool/.build", "Developer/site/node_modules"]
        let genuine = ["Developer/real/node_modules", "Developer/pkg/.build", "Developer/py/.venv", "Developer/ios/DerivedData"]

        let summary = try await cull(fixture, (forged + genuine).map(artifact))
        XCTAssertEqual(summary.outcomes.prefix(forged.count).map(\.status), Array(repeating: .failed, count: forged.count))
        XCTAssertEqual(summary.outcomes.suffix(genuine.count).map(\.status), Array(repeating: .removed, count: genuine.count))
        for relative in forged { XCTAssertTrue(fixture.exists(relative), "\(relative) must be left alone") }
        for relative in genuine { XCTAssertFalse(fixture.exists(relative), "\(relative) should be gone") }
        XCTAssertTrue(fixture.exists("Documents/Research/target/findings.pdf"))
    }

    func testItemsWithoutAScopeAreRefused() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Caches/com.some.app/x")
        let target = CullItem(
            id: "x", categoryID: "x", title: "x", paths: [fixture.path("Library/Caches/com.some.app")],
            action: .deleteContents, scope: nil, bytes: 1, selectedByDefault: true
        )
        let summary = try await cull(fixture, [target])
        XCTAssertEqual(summary.outcomes.map(\.status), [.failed])
        XCTAssertTrue(fixture.exists("Library/Caches/com.some.app/x"))
    }

    func testAFolderSwappedForASymlinkIsNotFollowed() async throws {
        let fixture = try Fixture()
        fixture.file("Documents/precious/novel.txt")
        fixture.dir("Library/Caches")
        // After the scan, the cache folder has become a symlink to something precious.
        fixture.symlink("Library/Caches/com.some.app", to: fixture.path("Documents/precious"))

        let emptying = item(fixture, ["Library/Caches/com.some.app"], action: .deleteContents, scope: .under([fixture.path("Library/Caches")]))
        var summary = try await cull(fixture, [emptying])
        XCTAssertEqual(summary.outcomes.map(\.status), [.failed])
        XCTAssertTrue(fixture.exists("Documents/precious/novel.txt"))

        // Deleting the item itself removes the link and leaves its target alone.
        let deleting = item(fixture, ["Library/Caches/com.some.app"], action: .delete, scope: .under([fixture.path("Library/Caches")]))
        summary = try await cull(fixture, [deleting])
        XCTAssertEqual(summary.outcomes.map(\.status), [.removed])
        XCTAssertFalse(fixture.exists("Library/Caches/com.some.app"))
        XCTAssertTrue(fixture.exists("Documents/precious/novel.txt"))
    }

    func testAParentSwappedForASymlinkIsRefused() async throws {
        let fixture = try Fixture()
        fixture.file("Documents/precious/DerivedData/App-abcdefghijklmnopqrstuvwxyzab/novel.txt")
        fixture.dir("Library/Developer/Xcode")
        fixture.symlink("Library/Developer/Xcode/DerivedData", to: fixture.path("Documents/precious/DerivedData"))

        let target = item(
            fixture, ["Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab"],
            action: .delete, scope: .under([fixture.path("Library/Developer/Xcode/DerivedData")])
        )
        let summary = try await cull(fixture, [target])
        XCTAssertEqual(summary.outcomes.map(\.status), [.failed])
        XCTAssertTrue(summary.outcomes[0].message?.contains("symlink") ?? false)
        XCTAssertTrue(fixture.exists("Documents/precious/DerivedData/App-abcdefghijklmnopqrstuvwxyzab/novel.txt"))
    }

    // MARK: Commands

    func testCommandsRunThroughTheRunner() async throws {
        let fixture = try Fixture()
        let runner = FakeRunner()
        let udid = "2CC7A2C1-E1A7-4633-911A-DB60BDEB97F0"
        let target = CullItem(
            id: "sim|\(udid)", categoryID: "sim.unavailable", title: "iPhone", paths: [],
            action: .command(["/usr/bin/xcrun", "simctl", "delete", udid]), scope: nil, bytes: 5_000,
            selectedByDefault: true
        )
        let summary = try await cull(fixture, [target], runner: runner)
        XCTAssertEqual(summary.outcomes.map(\.status), [.removed])
        XCTAssertEqual(runner.invocations, [["/usr/bin/xcrun", "simctl", "delete", udid]])
        XCTAssertEqual(summary.deletedBytes, 5_000)
    }

    func testFailedCommandsReportTheLastLineOfOutput() async throws {
        let fixture = try Fixture()
        let runner = FakeRunner()
        let udid = "2CC7A2C1-E1A7-4633-911A-DB60BDEB97F0"
        runner.respond(to: "simctl erase \(udid)", with: "An error was encountered\nUnable to erase in current state: Booted\n", status: 149)
        let target = CullItem(
            id: "sim|\(udid)", categoryID: "sim.data", title: "iPhone", paths: [],
            action: .command(["/usr/bin/xcrun", "simctl", "erase", udid]), scope: nil, bytes: 5_000,
            selectedByDefault: false
        )
        let summary = try await cull(fixture, [target], runner: runner)
        XCTAssertEqual(summary.outcomes.map(\.status), [.failed])
        XCTAssertEqual(summary.outcomes[0].message, "Unable to erase in current state: Booted")
    }

    func testDisallowedCommandsNeverReachTheRunner() async throws {
        let fixture = try Fixture()
        let runner = FakeRunner()
        let commands: [[String]] = [
            ["/bin/rm", "-rf", fixture.home],
            ["/usr/bin/xcrun", "simctl", "delete", "all"],
            ["/usr/bin/xcrun", "simctl", "erase", "all"],
        ]
        let items = commands.enumerated().map { index, command in
            CullItem(id: "c\(index)", categoryID: "x", title: "x", paths: [], action: .command(command), scope: nil, bytes: 1, selectedByDefault: true)
        }
        let summary = try await cull(fixture, items, runner: runner)
        XCTAssertEqual(summary.outcomes.map(\.status), [.failed, .failed, .failed])
        XCTAssertEqual(runner.invocations, [])
    }

    func testCommandsWithoutARunnerFail() async throws {
        let fixture = try Fixture()
        let target = CullItem(
            id: "sim", categoryID: "sim.unavailable", title: "iPhone", paths: [],
            action: .command(["/usr/bin/xcrun", "simctl", "delete", "2CC7A2C1-E1A7-4633-911A-DB60BDEB97F0"]),
            scope: nil, bytes: 1, selectedByDefault: true
        )
        let summary = try await cull(fixture, [target])
        XCTAssertEqual(summary.outcomes.map(\.status), [.failed])
    }

    // MARK: Environment

    func testHomeMustBeARealFolderThatBelongsToYou() {
        // "/tmp" resolves to /private/tmp on macOS, and /usr/bin is plenty deep: it is ownership,
        // not depth, that rules shared and system folders out.
        for bad in ["/", "/tmp", "/usr/bin", "/usr/share/man", "relative/path", "/definitely/not/here"] {
            XCTAssertThrowsError(try CullEnvironment(home: bad), "\(bad) should be rejected")
        }
    }

    func testAFileIsNotAHome() throws {
        let fixture = try Fixture()
        fixture.file("not-a-folder")
        XCTAssertThrowsError(try CullEnvironment(home: fixture.path("not-a-folder")))
    }

    func testHomeIsCanonicalized() throws {
        let fixture = try Fixture()
        fixture.dir("real-home")
        fixture.symlink("alias-home", to: fixture.path("real-home"))
        let environment = try CullEnvironment(home: fixture.path("alias-home"))
        XCTAssertEqual(environment.home, fixture.path("real-home"))
    }

    func testProgressCountsEveryItem() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Caches/a.b.c/x")
        fixture.file("Library/Caches/d.e.f/x")
        let scope = PathScope.under([fixture.path("Library/Caches")])
        let items = ["a.b.c", "d.e.f"].map { item(fixture, ["Library/Caches/\($0)"], action: .deleteContents, scope: scope) }

        let recorder = ProgressRecorder()
        let summary = await Culler(environment: try fixture.environment()).cull(items) { recorder.add($0) }
        XCTAssertEqual(summary.succeededCount, 2)
        XCTAssertEqual(recorder.values.map(\.completed), [0, 1, 2])
        XCTAssertEqual(recorder.values.last?.bytesSoFar, 16_384)
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [CullProgress] = []

    func add(_ progress: CullProgress) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(progress)
    }

    var values: [CullProgress] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
