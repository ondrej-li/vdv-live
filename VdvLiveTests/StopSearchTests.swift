import XCTest
@testable import VdvLive

/// The stop search, as it is typed on a phone: hurriedly, without diacritics, in whatever
/// case the keyboard offers.
final class StopSearchTests: XCTestCase {
    private let table = StopPositions.shipped

    func testFindsAStopTypedWithoutDiacritics() {
        XCTAssertTrue(table.names(matching: "nova brtnice").contains("Zašovice,Nová Brtnice"))
        XCTAssertEqual(table.names(matching: "nova brtnice"),
                       table.names(matching: "Nová Brtnice"))
    }

    func testFindsAStopTypedWithoutItsHacek() {
        XCTAssertTrue(table.names(matching: "zasovice").contains("Zašovice"))
    }

    func testIgnoresCase() {
        XCTAssertEqual(table.names(matching: "TELČ"), table.names(matching: "telč"))
        XCTAssertTrue(table.names(matching: "telc").contains("Telč,aut.nádr."))
    }

    /// People leave the punctuation out, so `telc aut nadr` has to reach `Telč,aut.nádr.`.
    func testIgnoresPunctuationAndSpacing() {
        XCTAssertTrue(table.names(matching: "telc aut nadr").contains("Telč,aut.nádr."))
        XCTAssertTrue(table.names(matching: "telc,aut.nadr").contains("Telč,aut.nádr."))
    }

    func testNamesBeginningWithTheQueryComeFirst() {
        let names = table.names(matching: "telc")

        XCTAssertFalse(names.isEmpty)
        XCTAssertTrue(StopPositions.lookupKey(for: names[0]).hasPrefix("telc"),
                      "first result was \(names[0])")
    }

    func testAnEmptyQueryOffersNothing() {
        XCTAssertTrue(table.names(matching: "").isEmpty)
        XCTAssertTrue(table.names(matching: "   ").isEmpty)
    }

    func testStarredStopsCanBeLeftOut() {
        let starred: Set<String> = ["Telč,aut.nádr."]
        let names = table.names(matching: "telc") { starred.contains($0) }

        XCTAssertFalse(names.contains("Telč,aut.nádr."))
    }

    func testTheResultCountIsBounded() {
        XCTAssertEqual(table.names(matching: "a", limit: 5).count, 5)
    }
}
