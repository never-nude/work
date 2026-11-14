import XCTest
@testable import CullCore

/// Builds a lived-in home folder and checks the one property that matters most:
/// whatever gets culled, the things a person cannot get back are still there afterwards.
final class EndToEndTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(Fixture.isRoot, "Cull refuses to delete as root, so these cannot run as root")
    }

    private let staleBuild = "Library/Developer/Xcode/DerivedData/OldApp-abcdefghijklmnopqrstuvwxyzab"
    private let freshBuild = "Library/Developer/Xcode/DerivedData/Archivist-bcdefghijklmnopqrstuvwxyzabc"
    private let deviceSupport = "Library/Developer/Xcode/iOS DeviceSupport"
    private let simulator = "Library/Developer/CoreSimulator/Devices/2CC7A2C1-E1A7-4633-911A-DB60BDEB97F0"

    /// Never to be removed, whatever is selected.
    private var precious: [String] {
        [
            "Documents/thesis.docx",
            "Documents/Taxes/2025.pdf",
            "Desktop/screenshot.png",
            "Pictures/Photos Library.photoslibrary/database/Photos.sqlite",
            "Music/song.m4a",
            "Movies/clip.mov",
            ".ssh/id_ed25519",
            ".ssh/config",
            ".gnupg/secring.gpg",
            ".aws/credentials",
            ".config/gh/hosts.yml",
            ".zshrc",
            ".gitconfig",
            ".npmrc",
            ".npm/config-should-stay",
            ".cache/huggingface/token",
            ".ollama/models/blobs/sha256-abc",
            "Library/Messages/chat.db",
            "Library/Messages/Attachments/aa/photo.heic",
            "Library/Mail/V10/INBOX.mbox/1.emlx",
            "Library/Mobile Documents/com~apple~CloudDocs/notes.txt",
            "Library/Keychains/login.keychain-db",
            "Library/Preferences/com.some.app.plist",
            "Library/Application Support/Archivist/archive.sqlite",
            "Library/Application Support/Archivist/Cache/thumbnails.db",
            "Library/Application Support/Slack/Local Storage/leveldb/000005.ldb",
            "Library/Application Support/Slack/Cookies",
            "Library/Application Support/Slack/storage/root-state.json",
            "Library/Application Support/Code/User/settings.json",
            "Library/Application Support/Code/User/workspaceStorage/abc/state.vscdb",
            "Library/Application Support/Google/Chrome/Default/History",
            "Library/Application Support/Google/Chrome/Default/Bookmarks",
            "Library/Application Support/Google/Chrome/Default/Login Data",
            "Library/Application Support/AddressBook/AddressBook-v22.abcddb",
            "Library/Containers/com.dev.sandboxed/Data/Documents/precious.txt",
            "Library/Containers/com.dev.sandboxed/Data/Library/Preferences/settings.plist",
            "Library/Containers/com.apple.mail/Data/Library/Caches/envelope",
            "Library/Caches/com.apple.Safari/WebKitCache/x",
            "Library/Caches/com.apple.bird/session.db",
            "Library/Caches/CloudKit/db",
            "Library/Caches/pypoetry/virtualenvs/proj/bin/python",
            "Library/Developer/Xcode/UserData/CodeSnippets/a.codesnippet",
            "Library/Developer/Xcode/UserData/FontAndColorThemes/Mine.xccolortheme",
            "\(simulator)/data/Containers/Data/Application/app.sqlite",
            "Library/iTunes/iTunes Library.itl",
            "Developer/active/package.json",
            "Developer/active/package-lock.json",
            "Developer/active/src/App.tsx",
            "Developer/active/.env",
            "Developer/active/.git/HEAD",
            "Developer/old-site/package.json",
            "Developer/old-site/package-lock.json",
            "Developer/old-site/src/App.tsx",
            "Developer/old-site/.env",
            "Developer/old-site/.git/HEAD",
            "Developer/old-site/.git/objects/aa/bbccdd",
            "Developer/old-site/public/logo.png",
            "Developer/old-site/dist/bundle.js",
            "Developer/old-site/build/out.js",
            "Developer/notes/node_modules/readme.txt",
            "Developer/Thing.app/Contents/Resources/node_modules/x.js",
            "Downloads/just-arrived.zip",
        ]
    }

    /// Removed by a cull of the default selection.
    private var culledByDefault: [String] {
        [
            ".npm/_cacache/content-v2/blob",
            ".npm/_logs/debug.log",
            "Library/Caches/Homebrew/downloads/formula.tar.gz",
            "Library/Caches/pip/http/a",
            "Library/Caches/org.swift.swiftpm/repositories/pack",
            "Library/Caches/pypoetry/cache/x",
            "Library/Caches/com.spotify.client/Data/chunk",
            "Library/Caches/com.apple.dt.Xcode/Downloads/x",
            "Library/Logs/DiagnosticReports/App.ips",
            "Library/Application Support/Slack/Cache/Cache_Data/data_1",
            "Library/Application Support/Slack/Code Cache/js/index",
            "Library/Application Support/Slack/GPUCache/data_0",
            "Library/Application Support/Slack/Service Worker/CacheStorage/abc/1",
            "Library/Application Support/Code/GPUCache/data_0",
            "Library/Application Support/Code/CachedData/abc/x.code",
            "Library/Application Support/Google/Chrome/Default/Code Cache/js/x",
            "Library/Containers/com.dev.sandboxed/Data/Library/Caches/blob",
            "\(staleBuild)/Build/Products/Debug/OldApp",
            "Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Foundation.pcm",
            "\(deviceSupport)/iPhone15,2 17.5 (21F90)/Symbols/x",
            "Library/Developer/Xcode/UserData/Previews/Simulator Devices/x",
            "Library/Developer/CoreSimulator/Caches/dyld/x",
            "Library/iTunes/iPhone Software Updates/iPhone_Restore.ipsw",
            "Developer/old-site/node_modules/react/index.js",
            "Developer/old-site/.next/cache/webpack/x",
        ]
    }

    /// Offered, but left alone unless explicitly selected.
    private var offeredOnly: [String] {
        [
            "\(freshBuild)/Build/Products/Debug/Archivist",
            "\(deviceSupport)/iPhone18,1 26.1 (23B85)/Symbols/x",
            "Developer/active/node_modules/react/index.js",
            "Library/Caches/mysterydaemon/state",
            "Library/Caches/ms-playwright/chromium-1/chrome",
            ".cache/huggingface/hub/models--org--big/blob",
            "Downloads/old-installer.dmg",
            "Downloads/receipt-2019.pdf",
            ".Trash/old-export.zip",
            "Library/Application Support/MobileSync/Backup/00008110-001A/Manifest.db",
            "Library/Developer/Xcode/Archives/2025-03-01/App.xcarchive/dSYMs/x",
        ]
    }

    private func makeHome() throws -> Fixture {
        let fixture = try Fixture()
        for relative in precious + culledByDefault + offeredOnly { fixture.file(relative) }
        // Folders that are emptied in place must survive as empty folders.
        fixture.file("Library/Caches/com.spotify.client/Data/second-chunk")
        // What makes the fresh things fresh.
        fixture.touch("\(freshBuild)/Build/Products/Debug/Archivist", daysAgo: 1)
        fixture.touch("Developer/active/src/App.tsx", daysAgo: 1)
        fixture.touch("Downloads/just-arrived.zip", daysAgo: 1)
        fixture.touch("\(deviceSupport)/iPhone15,2 17.5 (21F90)", daysAgo: 300)
        fixture.touch("\(deviceSupport)/iPhone18,1 26.1 (23B85)", daysAgo: 20)
        return fixture
    }

    private func assertAllExist(_ paths: [String], in fixture: Fixture, _ why: String, file: StaticString = #filePath, line: UInt = #line) {
        for relative in paths {
            XCTAssertTrue(fixture.exists(relative), "\(why): \(relative) is gone", file: file, line: line)
        }
    }

    func testScanningChangesNothing() async throws {
        let fixture = try makeHome()
        let before = fixture.snapshot()
        let report = try await fixture.scan()
        XCTAssertEqual(fixture.snapshot(), before)
        XCTAssertEqual(report.skippedNotes, [], "no rule may propose something the guard refuses")
        XCTAssertFalse(report.allItems.isEmpty)
    }

    func testEveryOfferedPathPassesTheGuardAndReviewItemsAreNeverPreselected() async throws {
        let fixture = try makeHome()
        let report = try await fixture.scan()
        let safetyGuard = SafetyGuard(home: fixture.home)
        for category in report.categories {
            for item in category.items {
                for path in item.paths {
                    XCTAssertNil(safetyGuard.refusal(for: path, action: item.action, scope: item.scope), path)
                }
                if category.tier == .review {
                    XCTAssertFalse(item.selectedByDefault, "\(item.title) is personal and must not be pre-selected")
                    if !item.paths.isEmpty, category.id != "trash" {
                        XCTAssertEqual(item.action, .trash, "\(item.title) must go to the Trash, not be deleted")
                    }
                }
            }
        }
    }

    func testDefaultCullRemovesExactlyWhatWasPreselected() async throws {
        let fixture = try makeHome()
        let report = try await fixture.scan()
        let selected = report.allItems.filter(\.selectedByDefault)
        XCTAssertFalse(selected.isEmpty)

        let before = fixture.snapshot()
        let summary = await Culler(environment: try fixture.environment()).cull(selected)
        let removed = before.subtracting(fixture.snapshot())

        XCTAssertEqual(summary.problems, [])
        XCTAssertEqual(summary.succeededCount, selected.count)
        assertAllExist(precious, in: fixture, "precious")
        assertAllExist(offeredOnly, in: fixture, "not selected")
        for relative in culledByDefault {
            XCTAssertFalse(fixture.exists(relative), "\(relative) should have been culled")
        }

        // Nothing went that was not inside something the report listed as selected.
        let selectedPaths = selected.flatMap(\.paths)
        for relative in removed {
            let full = fixture.path(relative)
            XCTAssertTrue(
                selectedPaths.contains { full == $0 || full.hasPrefix($0 + "/") },
                "\(relative) was removed without being part of a selected item"
            )
        }

        // Emptied in place, not removed.
        for folder in ["Library/Caches/com.spotify.client", ".npm/_cacache", "Library/Caches/Homebrew",
                       "Library/Application Support/Slack/Cache", "Library/Developer/Xcode/UserData/Previews"] {
            XCTAssertTrue(fixture.isEmptyDirectory(folder), "\(folder) should still exist, empty")
        }
        XCTAssertFalse(fixture.exists(staleBuild))
        XCTAssertFalse(fixture.exists("Developer/old-site/node_modules"))
    }

    func testCullingEverythingOfferedStillSparesEverythingPrecious() async throws {
        let fixture = try makeHome()
        let report = try await fixture.scan()
        let before = fixture.snapshot()

        let summary = await Culler(environment: try fixture.environment()).cull(report.allItems)

        XCTAssertEqual(summary.problems, [])
        assertAllExist(precious, in: fixture, "precious")
        XCTAssertGreaterThan(summary.trashedBytes, 0)

        // Personal files were moved to the Trash, not destroyed.
        for name in ["old-installer.dmg", "receipt-2019.pdf", "00008110-001A", "App.xcarchive"] {
            XCTAssertTrue(fixture.exists(".Trash/\(name)"), "\(name) should be in the Trash")
        }
        XCTAssertFalse(fixture.exists(".Trash/old-export.zip"), "what was already in the Trash is emptied")

        // Anything that vanished was either offered, or is now in the Trash.
        let offered = report.allItems.flatMap(\.paths)
        for relative in before.subtracting(fixture.snapshot()) {
            let full = fixture.path(relative)
            XCTAssertTrue(
                offered.contains { full == $0 || full.hasPrefix($0 + "/") },
                "\(relative) vanished without ever being offered"
            )
        }
    }

    func testASecondPassFindsNothingLeftToPreselect() async throws {
        let fixture = try makeHome()
        let first = try await fixture.scan()
        _ = await Culler(environment: try fixture.environment()).cull(first.allItems.filter(\.selectedByDefault))

        let second = try await fixture.scan()
        XCTAssertEqual(second.defaultSelection, [], "a default cull leaves nothing pre-selected behind")
        XCTAssertEqual(second.categories(in: .safe).flatMap(\.items).filter(\.selectedByDefault), [])
        // The things that were deliberately left alone are still on offer.
        XCTAssertNotNil(second.item("xcode.derivedData", titled: "Archivist"))
        XCTAssertNotNil(second.item("downloads.old", titled: "old-installer.dmg"))
    }

    func testReportsAndSummariesSurviveJSON() async throws {
        let fixture = try makeHome()
        let report = try await fixture.scan()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScanReport.self, from: try encoder.encode(report))
        XCTAssertEqual(decoded.allItems.map(\.id), report.allItems.map(\.id))
        XCTAssertEqual(decoded.totalBytes, report.totalBytes)
        XCTAssertEqual(decoded.allItems.map(\.action), report.allItems.map(\.action))
    }

    func testLargeThingsCullWillNotTouchAreReportedAsAdvisories() async throws {
        let fixture = try Fixture()
        fixture.file(".ollama/models/blobs/sha256-big", bytes: 300_000)
        var report = try await fixture.scan()
        XCTAssertEqual(report.advisories, [], "below the 1 GB advisory threshold")

        // Docker's image is one sparse file; only its allocated size counts.
        fixture.file("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", bytes: 50_000)
        report = try await fixture.scan()
        XCTAssertEqual(report.advisories, [])
        XCTAssertTrue(fixture.exists(".ollama/models/blobs/sha256-big"))
    }
}
