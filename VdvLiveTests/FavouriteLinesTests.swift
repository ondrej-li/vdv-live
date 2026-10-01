import XCTest
@testable import VdvLive

final class FavouriteLinesTests: XCTestCase {
    func testAFreshSetIsEmpty() {
        let lines = FavouriteLines()

        XCTAssertTrue(lines.isEmpty)
        XCTAssertEqual(lines.count, 0)
        XCTAssertFalse(lines.contains("420"))
    }

    func testNormalisesWhatTheUserTypes() {
        XCTAssertEqual(FavouriteLines.normalize("  420\n"), "420")
        XCTAssertEqual(FavouriteLines.normalize("e50"), "E50")
        XCTAssertEqual(FavouriteLines.normalize("  "), "")
    }

    func testPinningAndUnpinning() {
        var lines = FavouriteLines()

        lines.pin("420")
        lines.pin("337")

        XCTAssertTrue(lines.contains("420"))
        XCTAssertTrue(lines.contains("337"))
        XCTAssertEqual(lines.count, 2)

        lines.unpin("420")

        XCTAssertFalse(lines.contains("420"))
        XCTAssertEqual(lines.orderedForDisplay, ["337"])
    }

    func testToggleReportsTheStateAfterTheChange() {
        var lines = FavouriteLines()

        XCTAssertTrue(lines.toggle("420"))
        XCTAssertTrue(lines.contains("420"))

        XCTAssertFalse(lines.toggle("420"))
        XCTAssertFalse(lines.contains("420"))
    }

    func testIgnoresBlankInput() {
        var lines = FavouriteLines()

        lines.pin("   ")

        XCTAssertTrue(lines.isEmpty)
        XCTAssertFalse(lines.toggle(""))
        XCTAssertFalse(lines.contains(""))
    }

    func testMatchesRegardlessOfSurroundingWhitespace() {
        let lines = FavouriteLines(["420"])

        XCTAssertTrue(lines.contains("420"))
        XCTAssertTrue(lines.contains(" 420 "))
        XCTAssertTrue(lines.contains("420\n"))
        XCTAssertFalse(lines.contains("4200"))
    }

    func testSeedingNormalisesAndDeduplicates() {
        let lines = FavouriteLines([" 420 ", "420", "337"])

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.orderedForDisplay, ["337", "420"])
    }

    func testOrdersNumericCodesAscending() {
        let lines = FavouriteLines(["5907", "420", "18", "337"])

        XCTAssertEqual(lines.orderedForDisplay, ["18", "337", "420", "5907"])
    }

    func testPutsNumericCodesBeforeAlphanumericOnes() {
        let lines = FavouriteLines(["X1", "420", "AB"])

        XCTAssertEqual(lines.orderedForDisplay, ["420", "AB", "X1"])
    }

    func testEqualityIgnoresTheOrderLinesWereAdded() {
        XCTAssertEqual(FavouriteLines(["420", "337"]), FavouriteLines(["337", "420"]))
        XCTAssertNotEqual(FavouriteLines(["420"]), FavouriteLines(["337"]))
    }

    func testFilesOperatorPrefixedCodesUnderTheLineNumber() {
        // 764 and 841 are operators; both run a line 337.
        let lines = FavouriteLines(["764337", "841337", "764420"])

        XCTAssertEqual(lines.orderedForDisplay, ["337", "420"])
        XCTAssertTrue(lines.contains("337"))
        XCTAssertTrue(lines.contains("764337"))
        XCTAssertFalse(lines.contains("764338"))
    }
}
