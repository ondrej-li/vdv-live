import XCTest
@testable import VdvLive

final class CzechHolidaysTests: XCTestCase {
    private func day(_ text: String) throws -> ServiceDay {
        try XCTUnwrap(ServiceDay(archiveText: text))
    }

    func testMarksTheFixedHolidays() throws {
        for text in ["01012026", "01052026", "08052026", "05072026",
                     "06072026", "28092026", "28102026", "17112026",
                     "24122026", "25122026", "26122026"] {
            XCTAssertTrue(CzechHolidays.isHoliday(try day(text)), text)
        }
    }

    /// Easter moves, and so do the two days tied to it. 2026: 5 April.
    func testMarksGoodFridayAndEasterMonday() throws {
        XCTAssertEqual(CzechHolidays.easterSunday(year: 2026), try day("05042026"))
        XCTAssertTrue(CzechHolidays.isHoliday(try day("03042026")))
        XCTAssertTrue(CzechHolidays.isHoliday(try day("06042026")))
        XCTAssertFalse(CzechHolidays.isHoliday(try day("04042026")))
    }

    /// The computus has to be right across the range a timetable covers, so a few
    /// years are checked against the published dates.
    func testComputesEasterAcrossYears() {
        let expected = [
            2024: "31032024", 2025: "20042025", 2026: "05042026", 2027: "28032027",
            2028: "16042028", 2029: "01042029", 2030: "21042030"
        ]
        for (year, text) in expected {
            XCTAssertEqual(CzechHolidays.easterSunday(year: year),
                           ServiceDay(archiveText: text),
                           "Easter \(year)")
        }
    }

    func testAnOrdinaryDayIsNotAHoliday() throws {
        XCTAssertFalse(CzechHolidays.isHoliday(try day("20102026")))
        XCTAssertFalse(CzechHolidays.isHoliday(try day("27102026")))
    }

    func testWeekdaysAreNumberedMondayFirst() throws {
        XCTAssertEqual(try day("20102026").weekday, 2)  // Tuesday
        XCTAssertEqual(try day("24102026").weekday, 6)  // Saturday
        XCTAssertEqual(try day("25102026").weekday, 7)  // Sunday
    }
}
