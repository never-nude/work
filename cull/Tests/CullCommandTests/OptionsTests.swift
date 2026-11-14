import CullCore
import XCTest
@testable import cull

final class OptionsTests: XCTestCase {
    private func item(_ category: String, _ key: String, selected: Bool, bytes: Int64 = 1_000_000) -> CullItem {
        CullItem(
            id: category + "|" + key, categoryID: category, title: key, paths: [], action: .delete,
            scope: nil, bytes: bytes, selectedByDefault: selected
        )
    }

    private var report: ScanReport {
        ScanReport(categories: [
            CullCategory(id: "caches.packages", title: "Packages", blurb: "", tier: .safe, symbol: "", items: [
                item("caches.packages", "npm", selected: true),
                item("caches.packages", "pip", selected: true),
            ]),
            CullCategory(id: "xcode.derivedData", title: "DerivedData", blurb: "", tier: .rebuildable, symbol: "", items: [
                item("xcode.derivedData", "Old", selected: true),
                item("xcode.derivedData", "Fresh", selected: false),
            ]),
            CullCategory(id: "tools.downloads", title: "Tools", blurb: "", tier: .rebuildable, symbol: "", items: [
                item("tools.downloads", "Playwright", selected: false),
            ]),
            CullCategory(id: "trash", title: "Trash", blurb: "", tier: .review, symbol: "", items: [
                item("trash", "all", selected: false),
            ]),
        ])
    }

    private func selection(_ arguments: String...) throws -> Set<String> {
        try Options.parse(arguments).selection(for: report)
    }

    func testDefaultsDeleteNothingAndSelectOnlyWhatIsPreselected() throws {
        let options = try Options.parse([])
        XCTAssertFalse(options.apply)
        XCTAssertFalse(options.yes)
        XCTAssertEqual(options.selection(for: report), ["caches.packages|npm", "caches.packages|pip", "xcode.derivedData|Old"])
    }

    func testIncludeAddsCategoriesTiersAndSingleItems() throws {
        XCTAssertTrue(try selection("--include", "trash").contains("trash|all"))
        XCTAssertEqual(
            try selection("--include", "rebuildable"),
            ["caches.packages|npm", "caches.packages|pip", "xcode.derivedData|Old", "xcode.derivedData|Fresh", "tools.downloads|Playwright"]
        )
        let single = try selection("--include", "xcode.derivedData|Fresh")
        XCTAssertTrue(single.contains("xcode.derivedData|Fresh"))
        XCTAssertFalse(single.contains("tools.downloads|Playwright"))
        // The whole rebuildable tier never drags personal files along.
        XCTAssertFalse(try selection("--include", "rebuildable").contains("trash|all"))
    }

    func testExcludeRemovesCategoriesAndSingleItemsAndWinsOverInclude() throws {
        XCTAssertEqual(try selection("--exclude", "caches.packages"), ["xcode.derivedData|Old"])
        XCTAssertEqual(
            try selection("--exclude", "caches.packages|npm"),
            ["caches.packages|pip", "xcode.derivedData|Old"]
        )
        XCTAssertFalse(try selection("--include", "trash", "--exclude", "trash").contains("trash|all"))
        XCTAssertEqual(
            try selection("--include", "rebuildable", "--exclude", "xcode.derivedData|Fresh,tools.downloads"),
            ["caches.packages|npm", "caches.packages|pip", "xcode.derivedData|Old"]
        )
    }

    func testParsesEveryFlag() throws {
        let options = try Options.parse([
            "--apply", "-y", "--json", "-v", "--no-color", "--only", "trash, caches.packages",
            "--stale-days", "7", "--project-days", "60", "--download-days", "0", "--simulator-mb", "50",
            "--roots", "~/Developer,/abs/path", "--never", "/a/b", "--home", "/tmp/somewhere",
        ])
        XCTAssertTrue(options.apply && options.yes && options.json && options.verbose)
        XCTAssertEqual(options.color, false)
        XCTAssertEqual(options.only, ["trash", "caches.packages"])
        XCTAssertEqual(options.staleDays, 7)
        XCTAssertEqual(options.projectDays, 60)
        XCTAssertEqual(options.downloadDays, 0)
        XCTAssertEqual(options.simulatorFloorMegabytes, 50)
        XCTAssertEqual(options.roots, ["~/Developer", "/abs/path"])
        XCTAssertEqual(options.never, ["/a/b"])
        XCTAssertEqual(options.home, "/tmp/somewhere")
    }

    func testRejectsWhatItDoesNotUnderstand() {
        let bad: [[String]] = [
            ["--bogus"],
            ["--only"],
            ["--only", "not-a-category"],
            ["--include", "not-a-category"],
            ["--exclude", "not-a-category"],
            ["--stale-days", "soon"],
            ["--stale-days", "-3"],
            ["clean"],
        ]
        for arguments in bad {
            XCTAssertThrowsError(try Options.parse(arguments), "\(arguments) should be rejected")
        }
    }

    func testRelativePathsBecomeAbsoluteAndTildeIsLeftForTheEngine() {
        XCTAssertEqual(Options.expand("/abs"), "/abs")
        XCTAssertEqual(Options.expand("~/Developer"), "~/Developer")
        XCTAssertTrue(Options.expand("relative").hasSuffix("/relative"))
        XCTAssertTrue(Options.expand("relative").hasPrefix("/"))
    }

    func testEveryCategoryIdIsAcceptedByOnly() throws {
        for entry in CullCatalog.entries {
            XCTAssertNoThrow(try Options.parse(["--only", entry.id]))
        }
    }
}
