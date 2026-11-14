import XCTest
@testable import CullCore

/// The guard is the last line of defence, so these tests are deliberately paranoid.
final class SafetyGuardTests: XCTestCase {
    let home = "/Users/sam"
    var safetyGuard: SafetyGuard { SafetyGuard(home: home) }

    private func under(_ relative: String...) -> PathScope {
        .under(relative.map { home + "/" + $0 })
    }

    private func assertAllowed(
        _ relative: String, _ scope: PathScope, _ action: ItemAction = .delete,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let reason = safetyGuard.refusal(for: home + "/" + relative, action: action, scope: scope)
        XCTAssertNil(reason, "\(relative) should be allowed", file: file, line: line)
    }

    private func assertRefused(
        _ path: String, _ scope: PathScope?, _ action: ItemAction = .delete,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertNotNil(
            safetyGuard.refusal(for: path, action: action, scope: scope),
            "\(path) should be refused", file: file, line: line
        )
    }

    /// Refused whatever the action.
    private func assertAlwaysRefused(_ path: String, _ scope: PathScope?, file: StaticString = #filePath, line: UInt = #line) {
        for action in [ItemAction.delete, .deleteContents, .trash] {
            assertRefused(path, scope, action, file: file, line: line)
        }
    }

    /// A scope so wide that only the guard's own lists stand in the way.
    private var anywhere: PathScope {
        .under([
            home + "/Library", home + "/Library/Caches", home + "/Documents", home + "/Desktop",
            home + "/Developer", home + "/.ssh", home + "/.config", home + "/Pictures", home + "/.Trash",
            home + "/.npm", home + "/Music", home + "/Movies", home + "/.aws", home + "/Downloads",
        ])
    }

    // MARK: What is allowed

    func testAllowsTheKnownCullableLocations() {
        assertAllowed("Library/Caches/com.spotify.client", under("Library/Caches"))
        assertAllowed("Library/Caches/com.apple.dt.Xcode", under("Library/Caches"))
        assertAllowed("Library/Caches/Homebrew", under("Library/Caches"))
        assertAllowed("Library/Logs/DiagnosticReports", under("Library/Logs"))
        assertAllowed(".npm/_cacache", under(".npm"))
        assertAllowed(".yarn/berry/cache", under(".yarn/berry"))
        assertAllowed(".bun/install/cache", under(".bun/install"))
        assertAllowed(".cache/pip", under(".cache"))
        assertAllowed(".cache/huggingface/hub/models--org--name", under(".cache/huggingface/hub"))
        assertAllowed(".gradle/caches", under(".gradle"))
        assertAllowed(".cargo/registry/cache", under(".cargo/registry"))
        assertAllowed("Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab", under("Library/Developer/Xcode/DerivedData"))
        assertAllowed("Library/Developer/Xcode/iOS DeviceSupport/iPhone17,1 18.5 (22F76)", under("Library/Developer/Xcode/iOS DeviceSupport"))
        assertAllowed("Library/Developer/Xcode/Archives/2026-01-02/App 1-2-26.xcarchive", under("Library/Developer/Xcode/Archives"), .trash)
        assertAllowed("Library/Developer/Xcode/UserData/Previews", under("Library/Developer/Xcode/UserData"))
        assertAllowed("Library/Developer/Xcode/DocumentationCache", under("Library/Developer/Xcode"))
        assertAllowed("Library/Developer/CoreSimulator/Caches", under("Library/Developer/CoreSimulator"))
        assertAllowed("Library/Developer/XCTestDevices", under("Library/Developer"))
        assertAllowed("Library/Application Support/MobileSync/Backup/00008110-000A", under("Library/Application Support/MobileSync/Backup"), .trash)
        assertAllowed("Library/Application Support/Slack/Cache", under("Library/Application Support"))
        assertAllowed("Library/Application Support/Slack/Service Worker/CacheStorage", under("Library/Application Support"))
        assertAllowed("Library/Application Support/Google/Chrome/Profile 1/Code Cache", under("Library/Application Support"))
        assertAllowed("Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches", under("Library/Containers"))
        assertAllowed("Library/Containers/com.apple.Safari/Data/Library/Caches", under("Library/Containers"))
        assertAllowed("Library/iTunes/iPhone Software Updates", under("Library/iTunes"))
        assertAllowed("Library/pnpm/store", under("Library/pnpm"))
        assertAllowed(".Trash/old thing", under(".Trash"))
        assertAllowed("Downloads/installer.dmg", under("Downloads"), .trash)
        assertAllowed("Downloads/old folder", under("Downloads"), .trash)
        assertAllowed("Developer/app/node_modules", .artifact(root: home + "/Developer", names: ["node_modules"]))
        assertAllowed("Documents/GitHub/site/.next", .artifact(root: home + "/Documents", names: [".next"]))
    }

    // MARK: Structure

    func testRefusesAnythingOutsideHome() {
        assertRefused("/etc/passwd", .under(["/etc"]))
        assertRefused("/Users/other/Library/Caches/x", .under(["/Users/other/Library/Caches"]))
        assertRefused("/Users/sam-evil/Library/Caches/x", .under(["/Users/sam-evil/Library/Caches"]))
        assertRefused("/Users/samuel/Library/Caches/x", under("Library/Caches"))
        assertRefused("/", anywhere)
        assertRefused("", anywhere)
        assertRefused("Library/Caches/x", anywhere)
    }

    func testRefusesHomeAndItsDirectChildren() {
        assertRefused(home, anywhere)
        assertRefused(home + "/", anywhere)
        for name in ["Documents", "Desktop", "Downloads", "Library", ".Trash", ".npm", ".cache", "Developer"] {
            assertAlwaysRefused(home + "/" + name, anywhere)
        }
    }

    func testRefusesPathsThatAreNotNormalized() {
        assertRefused(home + "/Library/Caches/../Preferences/x", anywhere)
        assertRefused(home + "/Library/Caches/./x", anywhere)
        assertRefused(home + "/Library/Caches//x", anywhere)
        assertRefused(home + "/Library/Caches/x/", anywhere)
        assertRefused(home + "/Library/Caches/x\0/y", anywhere)
        assertRefused(home + "/Developer/app/../../Documents/node_modules", .artifact(root: home + "/Developer", names: ["node_modules"]))
    }

    func testRefusesWhenNoScopeIsDeclared() {
        assertRefused(home + "/Library/Caches/com.spotify.client", nil)
    }

    // MARK: Library is allow-listed

    func testRefusesEverythingInLibraryThatIsNotOnTheList() {
        let offLimits = [
            "Library/Messages/chat.db",
            "Library/Messages/Attachments/ab/photo.heic",
            "Library/Mail/V10/MailData/Envelope Index",
            "Library/Mobile Documents/com~apple~CloudDocs/notes.txt",
            "Library/CloudStorage/Dropbox/file",
            "Library/Keychains/login.keychain-db",
            "Library/Preferences/com.apple.finder.plist",
            "Library/Safari/History.db",
            "Library/Photos/Libraries/x",
            "Library/Calendars/Calendar.sqlitedb",
            "Library/Group Containers/group.com.apple.notes/NoteStore.sqlite",
            "Library/Application Support/AddressBook/AddressBook-v22.abcddb",
            "Library/Application Support/Archivist/archive.sqlite",
            "Library/Application Support/Slack/Local Storage/leveldb",
            "Library/Application Support/Slack/Cookies",
            "Library/Application Support/Code/User/workspaceStorage",
            "Library/Application Support/Code/User/settings.json",
            "Library/Application Support/com.apple.TCC/TCC.db",
            "Library/Application Support/MobileSync/Backup",
            "Library/Application Support/MobileSync/Backup/0000/Manifest.db",
            "Library/Developer/Xcode/UserData/CodeSnippets",
            "Library/Developer/Xcode/UserData/FontAndColorThemes/Mine.xccolortheme",
            "Library/Developer/Xcode/DerivedData",
            "Library/Developer/Xcode/Archives",
            "Library/Developer/Xcode/Archives/2026-01-02",
            "Library/Developer/CoreSimulator/Devices/ABCD/data",
            "Library/Developer/CoreSimulator/Devices",
            "Library/Containers/com.tinyspeck.slackmacgap/Data/Documents",
            "Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/x",
            "Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches/sub/dir",
            "Library/Containers/com.tinyspeck.slackmacgap",
            "Library/Containers/com.apple.mail/Data/Library/Caches",
            "Library/Containers/com.apple.Notes/Data/Library/Caches",
            "Library/Caches",
            "Library/Logs",
            "Library/iTunes/iTunes Library.itl",
            "Library/pnpm/global",
            "Library/Fonts/Custom.ttf",
            "Library/LaunchAgents/com.me.job.plist",
        ]
        for relative in offLimits {
            assertAlwaysRefused(home + "/" + relative, anywhere)
        }
    }

    func testRefusesAppleSystemCaches() {
        for name in ["com.apple.Safari", "com.apple.bird", "com.apple.nsurlsessiond", "com.apple.HomeKit",
                     "CloudKit", "FamilyCircle", "GeoServices", "PassKit", "com.apple"] {
            assertRefused(home + "/Library/Caches/" + name, under("Library/Caches"))
        }
        // Xcode's are the exception.
        assertAllowed("Library/Caches/com.apple.dt.Xcode", under("Library/Caches"))
        assertAllowed("Library/Caches/com.apple.dt.xcodebuild", under("Library/Caches"))
    }

    func testLibrarySpellingMustBeExact() {
        assertRefused(home + "/library/Caches/com.spotify.client", .under([home + "/library/Caches"]))
        assertRefused(home + "/LIBRARY/Caches/com.spotify.client", .under([home + "/LIBRARY/Caches"]))
    }

    // MARK: The rest of home

    func testRefusesSecretsAndHiddenFoldersOffTheList() {
        let offLimits = [
            ".ssh/id_ed25519", ".ssh/config", ".gnupg/private-keys-v1.d/key", ".aws/credentials",
            ".config/gh/hosts.yml", ".kube/config", ".docker/config.json", ".zsh_history/x",
            ".npm/_cacache/content-v2", ".npm/other", ".npmrc/x", ".yarn/berry", ".yarn/berry/cache/x",
            ".bun/bin/bun", ".gradle/gradle.properties", ".cargo/bin/rustc", ".cargo/registry/index",
            ".dotfiles/node_modules", ".Trash/folder/inner", ".trash/item",
        ]
        for relative in offLimits {
            assertAlwaysRefused(home + "/" + relative, anywhere)
        }
    }

    func testRefusesMediaFolders() {
        for relative in ["Pictures/Photos Library.photoslibrary", "Pictures/shot.png", "Music/Music/song.m4a",
                         "Movies/clip.mov", "pictures/shot.png", "Applications/Thing.app", "Public/Drop Box"] {
            assertRefused(home + "/" + relative, anywhere)
        }
        assertRefused(home + "/Pictures/project/node_modules", .artifact(root: home + "/Pictures", names: ["node_modules"]))
    }

    func testLookAlikeSpellingsDoNotSlipPastTheDenyLists() {
        // A case-insensitive volume treats these as Pictures, Music and com.apple.Safari.
        assertAlwaysRefused(home + "/Picture\u{017F}/shot.png", anywhere)
        assertRefused(home + "/Picture\u{017F}/site/node_modules", .artifact(root: home + "/Picture\u{017F}", names: ["node_modules"]))
        assertRefused(home + "/\u{FF2D}usic/site/node_modules", .artifact(root: home + "/\u{FF2D}usic", names: ["node_modules"]))
        assertAlwaysRefused(home + "/Library/Caches/COM.APPLE.Safari", under("Library/Caches"))
        assertAlwaysRefused(home + "/Library/Caches/com.apple.\u{017F}afari", under("Library/Caches"))
        assertRefused(home + "/Developer/app/.GIT/x/node_modules", .artifact(root: home + "/Developer", names: ["node_modules"]))
        XCTAssertEqual(SafetyGuard.folded("Picture\u{017F}"), "pictures")
    }

    func testRefusesGitMetadata() {
        assertRefused(home + "/Developer/app/.git", .artifact(root: home + "/Developer", names: [".git"]))
        assertRefused(home + "/Developer/app/.git/modules/x/node_modules", .artifact(root: home + "/Developer", names: ["node_modules"]))
        assertRefused(home + "/Developer/app/.GIT/node_modules", .artifact(root: home + "/Developer", names: ["node_modules"]))
    }

    // MARK: Your own folders

    func testOrdinaryFoldersOnlyGiveUpDownloadsAndBuildArtifacts() {
        // Even with a scope that matches perfectly, loose files in your folders are not cullable.
        let loose = [
            "Documents/thesis.docx", "Documents/Taxes/2025.pdf", "Desktop/screenshot.png",
            "Developer/app/src/main.swift", "Developer/app/package.json", "Developer/app/.env",
            "Sites/portfolio/index.html", "Downloads/folder/inner.txt", "iCloud Drive/file",
        ]
        for relative in loose {
            let parent = home + "/" + relative.split(separator: "/").dropLast().joined(separator: "/")
            assertAlwaysRefused(home + "/" + relative, .under([parent]))
        }
    }

    func testPersonalFilesCanOnlyGoToTheTrash() {
        let downloads = under("Downloads")
        assertRefused(home + "/Downloads/installer.dmg", downloads, .delete)
        assertRefused(home + "/Downloads/old folder", downloads, .deleteContents)

        let archives = under("Library/Developer/Xcode/Archives")
        let archive = home + "/Library/Developer/Xcode/Archives/2026-01-02/App.xcarchive"
        assertRefused(archive, archives, .delete)
        assertRefused(archive, archives, .deleteContents)

        let backups = under("Library/Application Support/MobileSync/Backup")
        let backup = home + "/Library/Application Support/MobileSync/Backup/00008110-000A"
        assertRefused(backup, backups, .delete)
        assertRefused(backup, backups, .deleteContents)
    }

    func testActionsAreBoundToWhereTheyMakeSense() {
        let root = home + "/Developer"
        // Build artifacts are deleted outright: never emptied in place, never trashed.
        assertRefused(root + "/app/node_modules", .artifact(root: root, names: ["node_modules"]), .deleteContents)
        assertRefused(root + "/app/node_modules", .artifact(root: root, names: ["node_modules"]), .trash)
        // The Trash cannot be "trashed" or emptied through a single entry.
        assertRefused(home + "/.Trash/thing", under(".Trash"), .trash)
        assertRefused(home + "/.Trash/thing", under(".Trash"), .deleteContents)
        // Commands never pass the path check; they have their own.
        assertRefused(home + "/Library/Caches/com.some.app", under("Library/Caches"), .command(["/bin/rm"]))
        // An artifact scope cannot be used to reach into Library, hidden folders or the Trash.
        assertRefused(home + "/Library/Caches/node_modules", .artifact(root: home + "/Library", names: ["node_modules"]))
        assertRefused(home + "/.cache/node_modules", .artifact(root: home + "/.cache", names: ["node_modules"]))
        assertRefused(home + "/.Trash/node_modules", .artifact(root: home + "/.Trash", names: ["node_modules"]))
    }

    // MARK: Scope

    func testHoldsPathsToTheirRulesScope() {
        // A perfectly cullable path, but not where this rule said it works.
        assertRefused(home + "/Library/Caches/com.spotify.client", under("Library/Logs"))
        assertRefused(home + "/Library/Caches/com.spotify.client", .under([]))
        assertRefused(home + "/Library/Caches/com.spotify.client", .under(["/Library/Caches"]))
        assertRefused(home + "/Downloads/file.zip", under("Downloads/sub"), .trash)
        assertRefused(home + "/Downloads/file.zip", under("Documents"), .trash)
        // The scope root itself is never a target.
        assertRefused(home + "/Library/Caches/com.spotify.client", under("Library/Caches/com.spotify.client"))
    }

    func testArtifactsMustHaveAKnownName() {
        let root = home + "/Developer"
        assertRefused(root + "/app/src", .artifact(root: root, names: ["src"]))
        assertRefused(root + "/app/.env", .artifact(root: root, names: [".env"]))
        assertRefused(root + "/app/node_modules", .artifact(root: root, names: [".build"]))
        assertRefused(root + "/app/node_modules/pkg", .artifact(root: root, names: ["node_modules"]))
        assertRefused(home + "/Other/app/node_modules", .artifact(root: root, names: ["node_modules"]))
        assertRefused(root + "/app/node_modules", .artifact(root: "/opt/code", names: ["node_modules"]))
        for name in SafetyGuard.artifactNames {
            assertAllowed("Developer/app/" + name, .artifact(root: root, names: [name]))
        }
    }

    // MARK: Commands

    func testAllowsOnlyThreeSimctlForms() {
        let udid = "2CC7A2C1-E1A7-4633-911A-DB60BDEB97F0"
        let xcrun = "/usr/bin/xcrun"
        XCTAssertNil(safetyGuard.refusal(forCommand: [xcrun, "simctl", "delete", udid]))
        XCTAssertNil(safetyGuard.refusal(forCommand: [xcrun, "simctl", "erase", udid]))
        XCTAssertNil(safetyGuard.refusal(forCommand: [xcrun, "simctl", "runtime", "delete", udid]))

        let refused: [[String]] = [
            [],
            [xcrun],
            [xcrun, "simctl", "delete"],
            [xcrun, "simctl", "delete", "all"],
            [xcrun, "simctl", "delete", "unavailable"],
            [xcrun, "simctl", "erase", "all"],
            [xcrun, "simctl", "delete", udid, "all"],
            [xcrun, "simctl", "runtime", "delete", "all"],
            [xcrun, "simctl", "runtime", "delete", "--notUsedSinceDays", "0"],
            [xcrun, "simctl", "runtime", "add", udid],
            [xcrun, "simctl", "shutdown", udid],
            [xcrun, "git", "clean", "-fdx"],
            ["/bin/rm", "-rf", home],
            ["/bin/sh", "-c", "xcrun simctl delete \(udid)"],
            ["xcrun", "simctl", "delete", udid],
            ["/usr/local/bin/xcrun", "simctl", "delete", udid],
        ]
        for command in refused {
            XCTAssertNotNil(safetyGuard.refusal(forCommand: command), "\(command) should be refused")
        }
    }
}
