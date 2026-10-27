import XCTest
@testable import VdvLive

final class StopNameMatchingTests: XCTestCase {
    func testFoldingDropsAccentsCaseAndPunctuation() {
        XCTAssertEqual(StopNameMatching.key(for: "Nová Brtnice"), "novabrtnice")
        XCTAssertEqual(StopNameMatching.key(for: "NOVA BRTNICE"), "novabrtnice")
        XCTAssertEqual(StopNameMatching.key(for: "Telč,aut.nádr."), "telcautnadr")
    }

    func testASpacedQueryWithoutAccentsFindsTheStop() {
        XCTAssertEqual(StopNameMatching.quality(of: "Nová Brtnice", matching: "nova brtnice"), .exact)
    }

    func testAPrefixIsAnAnswer() {
        XCTAssertEqual(StopNameMatching.quality(of: "Nová Brtnice", matching: "nova br"), .prefix)
    }

    func testTextInTheMiddleOfANameIsAnAnswer() {
        XCTAssertEqual(StopNameMatching.quality(of: "Zašovice,Nová Brtnice", matching: "brtnice"), .contains)
    }

    func testEveryTypedWordAsAWordPrefixIsAnAnswer() {
        XCTAssertEqual(StopNameMatching.quality(of: "Telč,aut.nádr.", matching: "telc nadr"), .words)
    }

    /// The typo this search exists for: one wrong letter in the middle.
    func testASlippedLetterStillFindsTheStop() {
        XCTAssertEqual(StopNameMatching.quality(of: "Nová Brtnice", matching: "nova betnice"), .fuzzy)
        XCTAssertEqual(StopNameMatching.quality(of: "Nová Brtnice", matching: "nová betnice"), .fuzzy)
    }

    func testSomethingElseEntirelyIsNotAnAnswer() {
        XCTAssertNil(StopNameMatching.quality(of: "Nová Brtnice", matching: "plzen"))
        XCTAssertNil(StopNameMatching.quality(of: "Nová Brtnice", matching: "z"))
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertNil(StopNameMatching.quality(of: "Nová Brtnice", matching: "   "))
    }

    func testToleranceGrowsWithTheQueryButStaysSmall() {
        XCTAssertEqual(StopNameMatching.tolerance(for: "z"), 1)
        XCTAssertEqual(StopNameMatching.tolerance(for: "novabrtnice"), 2)
        XCTAssertEqual(StopNameMatching.tolerance(for: "averylongstopnameindeed"), 3)
    }

    func testEditDistance() {
        XCTAssertEqual(StopNameMatching.editDistance("kitten", "sitting"), 3)
        XCTAssertEqual(StopNameMatching.editDistance("novabrtnice", "novabetnice"), 1)
        XCTAssertEqual(StopNameMatching.editDistance("", "abc"), 3)
        XCTAssertEqual(StopNameMatching.editDistance("abc", "abc"), 0)
    }

    /// The ranking a search list shows: direct answers before near misses.
    func testExactAndPrefixAnswersComeBeforeFuzzyOnes() {
        func stop(_ name: String) -> StopPosition {
            StopPosition(name: name, latitude: 0, longitude: 0, match: .name, accuracyMetres: 10)
        }
        let table = StopPositions(positions: [
            StopNameMatching.key(for: "Nová Brtnice,rozc."): stop("Nová Brtnice,rozc."),
            StopNameMatching.key(for: "Nová Brtnice"): stop("Nová Brtnice"),
            StopNameMatching.key(for: "Nová Ves"): stop("Nová Ves")
        ])

        let names = table.names(matching: "nova brtnice")

        XCTAssertEqual(names.first, "Nová Brtnice")
        XCTAssertTrue(names.contains("Nová Brtnice,rozc."))
        XCTAssertFalse(names.contains("Nová Ves"))
    }

    func testATypoStillReturnsTheStopThroughTheTable() {
        func stop(_ name: String) -> StopPosition {
            StopPosition(name: name, latitude: 0, longitude: 0, match: .name, accuracyMetres: 10)
        }
        let table = StopPositions(positions: [
            StopNameMatching.key(for: "Nová Brtnice"): stop("Nová Brtnice"),
            StopNameMatching.key(for: "Telč"): stop("Telč")
        ])

        XCTAssertEqual(table.names(matching: "nova betnice"), ["Nová Brtnice"])
    }
}
