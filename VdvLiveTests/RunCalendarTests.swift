import XCTest
@testable import VdvLive

final class RunCalendarTests: XCTestCase {
    private func day(_ text: String) throws -> ServiceDay {
        try XCTUnwrap(ServiceDay(archiveText: text))
    }

    private func date(_ text: String) -> RunCalendar {
        RunCalendar(rules: [.weekdays], exceptions: [
            .init(kind: .noService,
                  from: ServiceDay(archiveText: text)!,
                  to: ServiceDay(archiveText: text)!)
        ])
    }

    /// `X`: Monday to Friday, and not on a public holiday.
    func testWorkingDaysSkipWeekendsAndHolidays() throws {
        let calendar = RunCalendar(rules: [.weekdays])

        XCTAssertTrue(calendar.operates(on: try day("20102026")))   // Tuesday
        XCTAssertFalse(calendar.operates(on: try day("24102026")))  // Saturday
        XCTAssertFalse(calendar.operates(on: try day("25102026")))  // Sunday
        XCTAssertFalse(calendar.operates(on: try day("28102026")))  // Wednesday, a holiday
    }

    /// `+`: Sundays and every public holiday, whatever day it falls on. This is the
    /// rule that makes the holiday table matter for the other direction too.
    func testSundayServiceAlsoRunsOnHolidays() throws {
        let calendar = RunCalendar(rules: [.sundaysAndHolidays])

        XCTAssertTrue(calendar.operates(on: try day("25102026")))   // Sunday
        XCTAssertTrue(calendar.operates(on: try day("28102026")))   // Wednesday holiday
        XCTAssertFalse(calendar.operates(on: try day("20102026")))  // ordinary Tuesday
    }

    /// A single digit is one weekday, holidays included: a "runs on Tuesdays" bus
    /// still runs on a Tuesday holiday.
    func testASingleWeekdayRunsEvenOnAHoliday() throws {
        let calendar = RunCalendar(rules: [.weekday(2)])

        XCTAssertTrue(calendar.operates(on: try day("20102026")))
        XCTAssertFalse(calendar.operates(on: try day("21102026")))
    }

    /// A run the archive said nothing about is a run that runs: inventing silence is
    /// the one answer the archive never gave.
    func testNoRulesMeansEveryDay() throws {
        XCTAssertTrue(RunCalendar.everyDay.operates(on: try day("25102026")))
    }

    /// 4 November 2026 is an ordinary Wednesday; the note takes that one day out
    /// and leaves the Thursday alone.
    func testAnExceptionRemovesADay() throws {
        XCTAssertFalse(date("04112026").operates(on: try day("04112026")))
        XCTAssertTrue(date("04112026").operates(on: try day("05112026")))
    }

    /// "Goes only" cuts both ways: the day it names runs, every other day does not.
    func testServiceOnlyNarrowsToItsOwnDates() throws {
        let calendar = RunCalendar(rules: [.weekdays], exceptions: [
            .init(kind: .serviceOnly,
                  from: ServiceDay(archiveText: "09032026")!,
                  to: ServiceDay(archiveText: "15032026")!)
        ])

        XCTAssertTrue(calendar.operates(on: try day("10032026")))
        XCTAssertFalse(calendar.operates(on: try day("20032026")))
    }

    /// "Also goes" adds a day the header would have excluded.
    func testServiceAlsoAddsADay() throws {
        let calendar = RunCalendar(rules: [.weekdays], exceptions: [
            .init(kind: .serviceAlso,
                  from: ServiceDay(archiveText: "24102026")!,
                  to: nil)
        ])

        XCTAssertTrue(calendar.operates(on: try day("24102026")))   // Saturday
        XCTAssertFalse(calendar.operates(on: try day("25102026")))  // Sunday, not added
    }

    /// Odd and even weeks follow the ISO week number: 2026-10-20 is week 43 (odd),
    /// 2026-10-27 is week 44 (even).
    func testOddWeeksSkipTheEvenOnes() throws {
        let calendar = RunCalendar(rules: [.weekdays], exceptions: [
            .init(kind: .oddWeeks,
                  from: ServiceDay(archiveText: "01102026")!,
                  to: ServiceDay(archiveText: "31102026")!)
        ])

        XCTAssertTrue(calendar.operates(on: try day("20102026")))   // odd week
        XCTAssertFalse(calendar.operates(on: try day("27102026")))  // even week
    }

    func testReadsTheCalendarSymbols() {
        XCTAssertEqual(RunCalendar.rule(forSymbol: "X"), .weekdays)
        XCTAssertEqual(RunCalendar.rule(forSymbol: "+"), .sundaysAndHolidays)
        XCTAssertEqual(RunCalendar.rule(forSymbol: "3"), .weekday(3))
        XCTAssertNil(RunCalendar.rule(forSymbol: "@"))
        XCTAssertNil(RunCalendar.rule(forSymbol: "O"))
        XCTAssertNil(RunCalendar.rule(forSymbol: "x"))
    }
}
