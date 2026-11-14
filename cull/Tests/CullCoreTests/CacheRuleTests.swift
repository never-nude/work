import XCTest
@testable import CullCore

final class CacheRuleTests: XCTestCase {
    // MARK: Package managers

    func testFindsPackageManagerCaches() async throws {
        let fixture = try Fixture()
        fixture.file(".npm/_cacache/content-v2/sha512/aa/blob")
        fixture.file(".npm/_logs/2026-debug.log")
        fixture.file(".npm/config-should-stay")
        fixture.file("Library/Caches/Homebrew/downloads/formula.tar.gz")
        fixture.file("Library/Caches/pip/http/a/b")
        fixture.file("Library/Caches/org.swift.swiftpm/repositories/x/pack")

        let report = try await fixture.scan()
        let npm = try XCTUnwrap(report.item("caches.packages", titled: "npm"))
        XCTAssertEqual(Set(npm.paths), [fixture.path(".npm/_cacache"), fixture.path(".npm/_logs")])
        XCTAssertEqual(npm.action, .deleteContents)
        XCTAssertTrue(npm.selectedByDefault)
        XCTAssertNotNil(report.item("caches.packages", titled: "Homebrew downloads"))
        XCTAssertNotNil(report.item("caches.packages", titled: "pip"))
        XCTAssertNotNil(report.item("caches.packages", titled: "SwiftPM"))
        XCTAssertEqual(report.category("caches.packages")?.tier, .safe)
        XCTAssertEqual(report.skippedNotes, [])
    }

    func testPackageCachesAreNotListedTwice() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Caches/Homebrew/downloads/x")
        fixture.file("Library/Caches/pypoetry/cache/x")
        fixture.file("Library/Caches/pypoetry/virtualenvs/proj/bin/python")
        fixture.file("Library/Caches/ms-playwright/chromium-1/chrome")
        fixture.file(".cache/huggingface/hub/models--org--big/blob")
        fixture.file(".cache/pip/x")

        let report = try await fixture.scan()
        let generic = report.items("caches.apps").map(\.title)
        XCTAssertEqual(generic, [], "specific rules own these; the catch-all must leave them alone")
        // Poetry's virtualenvs live beside its cache and are not cache.
        let poetry = try XCTUnwrap(report.item("caches.packages", titled: "Poetry"))
        XCTAssertEqual(poetry.paths, [fixture.path("Library/Caches/pypoetry/cache")])
    }

    // MARK: Generic app caches

    func testGenericAppCachesFollowTheSelectionRules() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Caches/com.spotify.client/Data/chunk")
        fixture.file("Library/Caches/com.figma.Desktop/x")
        fixture.file("Library/Caches/Google/Chrome/Default/Cache/data_0")
        fixture.file("Library/Caches/mysterydaemon/state")
        fixture.file("Library/Caches/com.apple.Safari/WebKitCache/x")
        fixture.file("Library/Caches/com.apple.bird/session")
        fixture.file("Library/Caches/CloudKit/db")
        fixture.file("Library/Caches/com.apple.dt.Xcode/x")
        fixture.file("Library/Caches/.DS_Store")
        fixture.file("Library/Caches/loose-file.cache")
        fixture.file(".cache/pre-commit/repo/x")
        fixture.file(".cache/somethingelse/x")

        let report = try await fixture.scan(runningApps: ["com.figma.Desktop"])
        let items = Dictionary(uniqueKeysWithValues: report.items("caches.apps").map { ($0.title, $0) })

        XCTAssertEqual(Set(items.keys), [
            "com.spotify.client", "com.figma.Desktop", "Google Chrome", "mysterydaemon",
            "loose-file.cache", "pre-commit", "somethingelse",
        ])
        XCTAssertTrue(items["com.spotify.client"]!.selectedByDefault)
        XCTAssertTrue(items["Google Chrome"]!.selectedByDefault)
        XCTAssertTrue(items["pre-commit"]!.selectedByDefault)
        // Unrecognised names are offered but never pre-selected.
        XCTAssertFalse(items["mysterydaemon"]!.selectedByDefault)
        XCTAssertFalse(items["somethingelse"]!.selectedByDefault)
        // A running app keeps its cache until it quits.
        XCTAssertFalse(items["com.figma.Desktop"]!.selectedByDefault)
        XCTAssertNotNil(items["com.figma.Desktop"]!.caution)
        // Folders are emptied, loose files removed.
        XCTAssertEqual(items["com.spotify.client"]!.action, .deleteContents)
        XCTAssertEqual(items["loose-file.cache"]!.action, .delete)
        // Xcode's cache is listed by the Xcode rule instead.
        XCTAssertNotNil(report.item("caches.xcode", titled: "Xcode caches"))
        XCTAssertEqual(report.skippedNotes, [])
    }

    func testRunningHelperProcessesCountAsTheAppRunning() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Caches/com.tinyspeck.slackmacgap/x")
        let report = try await fixture.scan(runningApps: ["com.tinyspeck.slackmacgap.helper"])
        XCTAssertEqual(report.items("caches.apps").first?.selectedByDefault, false)
    }

    func testSymlinkedCacheFoldersAreInvisible() async throws {
        let fixture = try Fixture()
        fixture.file("external/big-cache/data", bytes: 50_000)
        fixture.symlink("Library/Caches/com.relocated.app", to: fixture.path("external/big-cache"))
        fixture.file("Library/Caches/com.normal.app/data")

        let report = try await fixture.scan()
        XCTAssertEqual(report.items("caches.apps").map(\.title), ["com.normal.app"])
    }

    func testAWholeRelocatedCachesFolderIsLeftAlone() async throws {
        let fixture = try Fixture()
        fixture.file("external/Caches/com.some.app/data", bytes: 50_000)
        fixture.dir("Library")
        fixture.symlink("Library/Caches", to: fixture.path("external/Caches"))

        let report = try await fixture.scan()
        XCTAssertNil(report.category("caches.apps"))
        XCTAssertNil(report.category("caches.packages"))
    }

    func testTinyItemsAreNotWorthListing() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Caches/com.small.app/x", bytes: 20_000)
        fixture.file("Library/Caches/com.large.app/x", bytes: 1_500_000)

        let report = try await fixture.scan(ScanOptions())
        XCTAssertEqual(report.items("caches.apps").map(\.title), ["com.large.app"])
    }

    // MARK: Chromium and Electron

    func testElectronAppsOfferOnlyTheirCacheFolders() async throws {
        let fixture = try Fixture()
        let slack = "Library/Application Support/Slack"
        fixture.file("\(slack)/Cache/Cache_Data/data_1")
        fixture.file("\(slack)/Code Cache/js/index")
        fixture.file("\(slack)/GPUCache/data_0")
        fixture.file("\(slack)/Service Worker/CacheStorage/abc/1")
        fixture.file("\(slack)/Service Worker/Database/000003.log")
        fixture.file("\(slack)/Local Storage/leveldb/000005.ldb")
        fixture.file("\(slack)/Cookies")
        fixture.file("\(slack)/storage/root-state.json")

        let report = try await fixture.scan()
        let item = try XCTUnwrap(report.item("caches.chromium", titled: "Slack"))
        XCTAssertEqual(Set(item.paths), [
            fixture.path("\(slack)/Cache"), fixture.path("\(slack)/Code Cache"),
            fixture.path("\(slack)/GPUCache"), fixture.path("\(slack)/Service Worker/CacheStorage"),
        ])
        XCTAssertEqual(item.action, .deleteContents)
        XCTAssertTrue(item.selectedByDefault)
        XCTAssertEqual(report.skippedNotes, [])
    }

    func testFoldersNamedCacheWithoutAChromiumProfileAreIgnored() async throws {
        let fixture = try Fixture()
        // Looks cache-like, but nothing says Chromium, so it might be anything.
        fixture.file("Library/Application Support/ThreadKeep/Cache/thumbnails.db")
        fixture.file("Library/Application Support/ThreadKeep/archive.sqlite")
        fixture.file("Library/Application Support/SomeTool/logs/a.log")

        let report = try await fixture.scan()
        XCTAssertNil(report.category("caches.chromium"))
    }

    func testRunningElectronAppsAreNotPreselected() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Application Support/Code/GPUCache/data_0")
        fixture.file("Library/Application Support/Code/CachedData/abc/x.code")
        fixture.file("Library/Application Support/discord/Code Cache/js/x")

        let report = try await fixture.scan(runningApps: ["com.microsoft.VSCode", "Discord"])
        XCTAssertEqual(report.item("caches.chromium", titled: "Code")?.selectedByDefault, false)
        XCTAssertEqual(report.item("caches.chromium", titled: "discord")?.selectedByDefault, false)
    }

    func testPasswordManagersAreOffLimits() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Application Support/1Password/GPUCache/data_0")
        fixture.file("Library/Application Support/Bitwarden/Code Cache/js/x")
        fixture.file("Library/Application Support/Ledger Live/GPUCache/data_0")

        let report = try await fixture.scan()
        XCTAssertNil(report.category("caches.chromium"))
    }

    func testBrowsersGatherCachesFromEveryProfile() async throws {
        let fixture = try Fixture()
        let chrome = "Library/Application Support/Google/Chrome"
        fixture.file("\(chrome)/Default/Code Cache/js/x")
        fixture.file("\(chrome)/Default/History")
        fixture.file("\(chrome)/Profile 2/GPUCache/data_0")
        fixture.file("\(chrome)/Profile 2/Bookmarks")
        fixture.file("\(chrome)/ShaderCache/data_0")
        fixture.file("\(chrome)/NotAProfile/Code Cache/x")

        let report = try await fixture.scan()
        let item = try XCTUnwrap(report.item("caches.chromium", titled: "Google Chrome"))
        XCTAssertEqual(Set(item.paths), [
            fixture.path("\(chrome)/Default/Code Cache"), fixture.path("\(chrome)/Profile 2/GPUCache"),
            fixture.path("\(chrome)/ShaderCache"),
        ])
        XCTAssertEqual(report.items("caches.chromium").count, 1, "the vendor folder is not also treated as an Electron app")
    }

    // MARK: Sandboxed apps

    func testContainerCachesNeedFullDiskAccess() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Containers/com.dev.sandboxed/Data/Library/Caches/x")
        fixture.file(".Trash/thing")

        let report = try await fixture.scan(fullDiskAccess: false)
        XCTAssertEqual(report.category("caches.containers")?.note, "Needs Full Disk Access")
        XCTAssertEqual(report.items("caches.containers"), [])
        XCTAssertEqual(report.category("trash")?.note, "Needs Full Disk Access")
        XCTAssertFalse(report.hasFullDiskAccess)
        XCTAssertTrue(report.notes.contains { $0.contains("Full Disk Access") })
    }

    func testContainerCachesSkipSystemAppsAndExtensions() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Containers/com.dev.sandboxed/Data/Library/Caches/x")
        fixture.file("Library/Containers/com.dev.sandboxed/Data/Documents/precious.txt")
        fixture.file("Library/Containers/com.apple.Safari/Data/Library/Caches/WebKit/x")
        fixture.file("Library/Containers/com.apple.mail/Data/Library/Caches/x")
        fixture.file("Library/Containers/com.apple.Notes/Data/Library/Caches/x")
        fixture.file("Library/Containers/5B1E3C6A-2D0F-4D52-9F0A-3C1B7C1E2A11/Data/Library/Caches/x")

        let report = try await fixture.scan()
        XCTAssertEqual(Set(report.items("caches.containers").map(\.title)), ["com.dev.sandboxed", "Safari"])
        XCTAssertEqual(
            report.item("caches.containers", titled: "com.dev.sandboxed")?.paths,
            [fixture.path("Library/Containers/com.dev.sandboxed/Data/Library/Caches")]
        )
        XCTAssertEqual(report.skippedNotes, [])
    }

    // MARK: Logs, tools

    func testLogsAreOfferedPerFolder() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Logs/DiagnosticReports/App-2026.ips")
        fixture.file("Library/Logs/Homebrew/build.log")
        fixture.file("Library/Logs/loose.log")
        fixture.file("Library/Logs/CoreSimulator/ABC/system.log")

        let report = try await fixture.scan()
        XCTAssertEqual(Set(report.items("logs.user").map(\.title)), ["DiagnosticReports", "Homebrew", "loose.log"])
        XCTAssertNotNil(report.item("caches.xcode", titled: "Simulator logs"))
    }

    func testDownloadedToolsAreOfferedButNeverPreselected() async throws {
        let fixture = try Fixture()
        fixture.file("Library/Caches/ms-playwright/chromium-1/chrome")
        fixture.file("Library/pnpm/store/v3/files/00/abc")
        fixture.file(".cache/huggingface/hub/models--meta--llama/blobs/abc")
        fixture.file(".cache/huggingface/hub/datasets--org--set/blobs/abc")
        fixture.file(".cache/huggingface/token")

        let report = try await fixture.scan()
        let items = report.items("tools.downloads")
        XCTAssertEqual(Set(items.map(\.title)), [
            "Playwright browsers", "pnpm store", "Hugging Face · meta/llama", "Hugging Face · dataset org/set",
        ])
        XCTAssertTrue(items.allSatisfy { !$0.selectedByDefault })
        XCTAssertEqual(report.category("tools.downloads")?.tier, .rebuildable)
        XCTAssertEqual(report.skippedNotes, [])
    }
}
