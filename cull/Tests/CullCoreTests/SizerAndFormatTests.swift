import XCTest
@testable import CullCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class SizerTests: XCTestCase {
    func testAddsUpAllocatedBytesAcrossATree() throws {
        let fixture = try Fixture()
        fixture.file("tree/a.bin", bytes: 100_000)
        fixture.file("tree/sub/b.bin", bytes: 200_000)
        fixture.file("tree/sub/deeper/c.bin", bytes: 50_000)
        fixture.dir("tree/empty")

        let measured = DirectorySizer.measure(fixture.path("tree"))
        // Allocation rounds up to whole blocks, so allow a little slack above the logical size.
        XCTAssertGreaterThanOrEqual(measured.bytes, 350_000)
        XCTAssertLessThan(measured.bytes, 350_000 + 64_000)
        XCTAssertEqual(measured.entries, 7)  // tree, a.bin, sub, b.bin, deeper, c.bin, empty
        XCTAssertFalse(measured.incomplete)
    }

    func testEmptyFoldersWeighNothing() throws {
        let fixture = try Fixture()
        fixture.dir("hollow/a/b/c")
        XCTAssertEqual(DirectorySizer.measure(fixture.path("hollow")).bytes, 0)
    }

    func testMissingPathWeighsNothing() throws {
        let fixture = try Fixture()
        XCTAssertEqual(DirectorySizer.measure(fixture.path("nope")), Measurement())
    }

    func testCountsHardLinkedFilesOnce() throws {
        let fixture = try Fixture()
        let original = fixture.file("links/original.bin", bytes: 300_000)
        for index in 1...4 {
            XCTAssertEqual(link(original, fixture.path("links/copy\(index).bin")), 0)
        }
        let measured = DirectorySizer.measure(fixture.path("links"))
        XCTAssertGreaterThanOrEqual(measured.bytes, 300_000)
        XCTAssertLessThan(measured.bytes, 300_000 + 16_000)
    }

    func testNeverFollowsSymlinks() throws {
        let fixture = try Fixture()
        fixture.file("elsewhere/huge.bin", bytes: 500_000)
        fixture.file("tree/small.bin", bytes: 10_000)
        fixture.symlink("tree/link-to-folder", to: fixture.path("elsewhere"))
        fixture.symlink("tree/link-to-file", to: fixture.path("elsewhere/huge.bin"))

        let measured = DirectorySizer.measure(fixture.path("tree"))
        XCTAssertLessThan(measured.bytes, 100_000, "the symlink targets must not be counted")

        // Measuring a symlink directly weighs the link, not what it points at.
        XCTAssertLessThan(DirectorySizer.measure(fixture.path("tree/link-to-folder")).bytes, 10_000)
    }

    func testReportsTheNewestChange() throws {
        let fixture = try Fixture()
        fixture.file("tree/old.bin")
        fixture.file("tree/deep/down/new.bin")
        fixture.touch("tree/deep/down/new.bin", daysAgo: 3)

        let newest = try XCTUnwrap(DirectorySizer.measure(fixture.path("tree")).newest)
        XCTAssertEqual(fixture.now.timeIntervalSince(newest) / 86_400, 3, accuracy: 0.01)
    }

    func testMarksUnreadableFoldersAsIncomplete() throws {
        try XCTSkipIf(Fixture.isRoot, "root can read everything")
        let fixture = try Fixture()
        fixture.file("tree/visible.bin", bytes: 10_000)
        fixture.file("tree/locked/hidden.bin", bytes: 10_000)
        XCTAssertEqual(chmod(fixture.path("tree/locked"), 0), 0)

        let measured = DirectorySizer.measure(fixture.path("tree"))
        XCTAssertTrue(measured.incomplete)
        XCTAssertGreaterThanOrEqual(measured.bytes, 10_000)
    }

    func testStopsWhenCancelled() throws {
        let fixture = try Fixture()
        for index in 0..<20 { fixture.file("tree/d\(index)/f.bin", bytes: 4_096) }
        let measured = DirectorySizer.measure(fixture.path("tree"), isCancelled: { true })
        XCTAssertTrue(measured.incomplete)
    }
}

final class FormatTests: XCTestCase {
    func testBytesUseDecimalUnitsLikeFinder() {
        XCTAssertEqual(Format.bytes(0), "0 bytes")
        XCTAssertEqual(Format.bytes(999), "999 bytes")
        XCTAssertEqual(Format.bytes(1_000), "1 KB")
        XCTAssertEqual(Format.bytes(14_300), "14 KB")
        XCTAssertEqual(Format.bytes(1_500_000), "1.5 MB")
        XCTAssertEqual(Format.bytes(512_000_000), "512 MB")
        XCTAssertEqual(Format.bytes(9_400_000_000), "9.4 GB")
        XCTAssertEqual(Format.bytes(38_200_000_000), "38.2 GB")
        XCTAssertEqual(Format.bytes(99_960_000_000), "100 GB")
        XCTAssertEqual(Format.bytes(494_000_000_000), "494 GB")
        XCTAssertEqual(Format.bytes(2_000_000_000_000), "2.0 TB")
        XCTAssertEqual(Format.bytes(-1_500_000), "-1.5 MB")
    }

    func testAgesReadNaturally() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func age(_ days: Double) -> String { Format.age(of: now.addingTimeInterval(-days * 86_400), now: now) }
        XCTAssertEqual(age(0.2), "today")
        XCTAssertEqual(age(1.5), "yesterday")
        XCTAssertEqual(age(5), "5 days ago")
        XCTAssertEqual(age(21), "3 weeks ago")
        XCTAssertEqual(age(95), "3 months ago")
        XCTAssertEqual(age(800), "2 years ago")
        XCTAssertEqual(age(-3), "just now")
    }

    func testTildeAbbreviatesOnlyRealHomePrefixes() {
        XCTAssertEqual(Format.tilde("/Users/sam/Library/Caches", home: "/Users/sam"), "~/Library/Caches")
        XCTAssertEqual(Format.tilde("/Users/sam", home: "/Users/sam"), "~")
        XCTAssertEqual(Format.tilde("/Users/samuel/x", home: "/Users/sam"), "/Users/samuel/x")
    }

    func testDiskPressure() {
        let gigabyte: Int64 = 1_000_000_000
        XCTAssertEqual(DiskSpace(total: 500 * gigabyte, free: 200 * gigabyte).pressure, .comfortable)
        XCTAssertEqual(DiskSpace(total: 500 * gigabyte, free: 18 * gigabyte).pressure, .tight)
        XCTAssertEqual(DiskSpace(total: 500 * gigabyte, free: 3 * gigabyte).pressure, .critical)
        XCTAssertEqual(DiskSpace(total: 500 * gigabyte, free: 1 * gigabyte, purgeable: 30 * gigabyte).available, 31 * gigabyte)
    }

    func testReadsRealDiskSpace() throws {
        let space = try XCTUnwrap(DiskSpace.of(path: NSTemporaryDirectory()))
        XCTAssertGreaterThan(space.total, 0)
        XCTAssertGreaterThanOrEqual(space.total, space.free)
    }
}
