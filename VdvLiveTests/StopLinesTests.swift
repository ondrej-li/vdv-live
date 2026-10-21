import XCTest
@testable import VdvLive

/// Which lines call at a stop. The timetables are per line, so this table is what turns
/// "a stop" into "the handful of timetables a board needs".
@MainActor
final class StopLinesTests: XCTestCase {
    func testTheBundleKnowsWhichLinesCallAtAHub() {
        let lines = StopPositions.bundled().lines(atStopNamed: "Telč,aut.nádr.")

        XCTAssertTrue(lines.contains("764350"), "the local line is missing from \(lines)")
        XCTAssertGreaterThan(lines.count, 10, "a hub in a town of five thousand: \(lines)")
    }

    /// The table is filed by the same washed-down key as the positions, so a name that
    /// arrived with different spacing or capitals finds the same lines.
    func testTheLookupWashesTheNameTheSameWayAsThePositions() {
        let table = StopPositions.bundled()

        XCTAssertEqual(table.lines(atStopNamed: "Telč,aut.nádr."),
                       table.lines(atStopNamed: "TELC, aut. nadr."))
    }

    func testAStopNobodyNamesHasNoLines() {
        XCTAssertTrue(StopPositions.bundled().lines(atStopNamed: "Nikde,nic").isEmpty)
        XCTAssertTrue(StopPositions.empty.lines(atStopNamed: "Telč,aut.nádr.").isEmpty)
    }

    /// Every code the table hands out has to be one the line mapping can turn into a
    /// timetable, or the board would show a stop with nothing on it.
    func testEveryLineTheTableNamesHasATimetable() {
        let mapping = LineTimetableStore.bundledMapping()
        let table = StopPositions.bundled()
        let codes = Set(table.lines(atStopNamed: "Telč,aut.nádr.")
                        + table.lines(atStopNamed: "Třebíč,aut.nádr."))

        XCTAssertFalse(codes.isEmpty)
        XCTAssertEqual(codes.subtracting(mapping.keys), [],
                       "codes with no timetable behind them")
    }
}
