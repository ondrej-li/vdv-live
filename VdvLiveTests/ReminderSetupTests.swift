import XCTest
@testable import VdvLive

final class ReminderSetupTests: XCTestCase {
    private func call(_ order: Int, _ name: String, at minutes: Int?) -> ScheduledCall {
        ScheduledCall(order: order,
                      stopID: String(order),
                      stopName: name,
                      arrival: nil,
                      departure: minutes.map { TimeOfDay(minutes: $0) },
                      distanceKilometres: nil,
                      isServed: minutes != nil)
    }

    private func timetable(lineNumber: String,
                           displayNumber: String,
                           runs: [ScheduledRun],
                           routeName: String = "") -> LineTimetable {
        LineTimetable(lineNumber: lineNumber,
                      displayNumber: displayNumber,
                      routeName: routeName,
                      operatorName: nil,
                      runs: runs)
    }

    // MARK: - Lines

    func testOnlyLinesThatActuallyCallThereAreOffered() {
        let calling = timetable(
            lineNumber: "764337",
            displayNumber: "337",
            runs: [ScheduledRun(serviceNumber: "1",
                                calls: [call(1, "Telč,,aut.nádr.", at: 7 * 60 + 5)])]
        )
        let skipping = timetable(
            lineNumber: "764420",
            displayNumber: "420",
            runs: [ScheduledRun(serviceNumber: "2",
                                calls: [call(1, "Jinde", at: 8 * 60)])]
        )

        let lines = ReminderSetup.lines(in: [skipping, calling], atStopNamed: "Telč,aut.nádr.")

        XCTAssertEqual(lines.map(\.lineNumber), ["764337"])
        XCTAssertEqual(lines.first?.displayNumber, "337")
        XCTAssertEqual(lines.first?.stopName, "Telč,,aut.nádr.",
                       "the archive's own spelling is what a reminder stores")
    }

    func testLinesAreOrderedByTheNumberAPassengerReads() {
        func line(_ number: String) -> LineTimetable {
            timetable(lineNumber: "764" + number,
                      displayNumber: number,
                      runs: [ScheduledRun(serviceNumber: "1",
                                          calls: [call(1, "Zastávka", at: 600)])])
        }

        let lines = ReminderSetup.lines(in: [line("420"), line("337"), line("101")],
                                        atStopNamed: "Zastávka")

        XCTAssertEqual(lines.map(\.displayNumber), ["101", "337", "420"])
    }

    /// A stop the run only passes is not a stop a notification can be made for.
    func testARunThatSkipsTheStopIsNotALineHere() {
        let passing = timetable(
            lineNumber: "764350",
            displayNumber: "350",
            runs: [ScheduledRun(serviceNumber: "3", calls: [call(1, "Okříšky", at: nil)])]
        )

        XCTAssertTrue(ReminderSetup.lines(in: [passing], atStopNamed: "Okříšky").isEmpty)
    }

    // MARK: - Services

    func testServicesAreTheRunsCallingThereByRunNumber() {
        let line = timetable(
            lineNumber: "764337",
            displayNumber: "337",
            runs: [
                ScheduledRun(serviceNumber: "10",
                             calls: [call(1, "Telč,,aut.nádr.", at: 9 * 60)]),
                ScheduledRun(serviceNumber: "2",
                             calls: [call(1, "Telč,,aut.nádr.", at: 7 * 60 + 5)]),
                ScheduledRun(serviceNumber: "4",
                             calls: [call(1, "Jinde", at: 10 * 60)])
            ]
        )

        let services = ReminderSetup.services(in: line, atStopNamed: "Telč,aut.nádr.")

        XCTAssertEqual(services.map(\.serviceNumber), ["2", "10"])
        XCTAssertEqual(services.first?.departure, TimeOfDay(minutes: 7 * 60 + 5))
    }

    func testAServiceKeepsTheArchivesStopSpelling() {
        let line = timetable(
            lineNumber: "764421",
            displayNumber: "421",
            runs: [ScheduledRun(serviceNumber: "9",
                                calls: [call(1, "Zašovice,Nová Brtnice", at: 7 * 60 + 42)])]
        )

        let services = ReminderSetup.services(in: line, atStopNamed: "Zašovice, Nová Brtnice")

        XCTAssertEqual(services.first?.stopName, "Zašovice,Nová Brtnice")
    }

    // MARK: - Which days a service runs

    func testWorkingDayRunsAreMondayToFriday() {
        let days = ReminderSetup.weekdays(from: RunCalendar(rules: [.weekdays]))

        XCTAssertEqual(days.days, Set(1...5))
        XCTAssertFalse(days.includesHolidays)
        XCTAssertFalse(days.hasExceptions)
    }

    func testSundayRunsAlsoRunOnPublicHolidays() {
        let days = ReminderSetup.weekdays(from: RunCalendar(rules: [.sundaysAndHolidays]))

        XCTAssertEqual(days.days, [7])
        XCTAssertTrue(days.includesHolidays)
    }

    func testASingleWeekdayRunSaysThatWeekday() {
        let days = ReminderSetup.weekdays(from: RunCalendar(rules: [.weekday(6)]))

        XCTAssertEqual(days.days, [6])
        XCTAssertFalse(days.includesHolidays)
    }

    func testARunWithNoStatedCalendarRunsEveryDay() {
        let days = ReminderSetup.weekdays(from: .everyDay)

        XCTAssertTrue(days.isEveryDay)
        XCTAssertFalse(days.hasExceptions)
    }

    func testWorkingDaysAreNamedThatWay() {
        let days = ReminderSetup.weekdays(from: RunCalendar(rules: [.weekdays]))

        XCTAssertEqual(days.restriction, .workingDays)
    }

    func testSaturdayAndSundayAreWeekends() {
        let days = ReminderSetup.weekdays(from: RunCalendar(rules: [.weekday(6), .weekday(7)]))

        XCTAssertEqual(days.restriction, .weekends)
    }

    func testSundayAloneIsSundays() {
        let days = ReminderSetup.weekdays(from: RunCalendar(rules: [.weekday(7)]))

        XCTAssertEqual(days.restriction, .sundays)
    }

    func testSundayServiceThatAlsoRunsOnHolidaysSaysSo() {
        let days = ReminderSetup.weekdays(from: RunCalendar(rules: [.sundaysAndHolidays]))

        XCTAssertEqual(days.restriction, .sundaysAndHolidays)
    }

    func testAnUnstatedCalendarIsEveryDay() {
        XCTAssertEqual(ReminderSetup.weekdays(from: .everyDay).restriction, .everyDay)
    }

    func testAnythingElseKeepsItsOwnDays() {
        let days = ReminderSetup.weekdays(from: RunCalendar(rules: [.weekday(3)]))

        XCTAssertEqual(days.restriction, .chosenDays([3]))
    }

    func testDatedExceptionsAreFlagged() throws {
        let exception = RunCalendar.Exception(kind: .noService,
                                              from: try XCTUnwrap(ServiceDay(archiveText: "22122026")),
                                              to: try XCTUnwrap(ServiceDay(archiveText: "02012027")))
        let days = ReminderSetup.weekdays(from: RunCalendar(rules: [.weekdays],
                                                            exceptions: [exception]))

        XCTAssertTrue(days.hasExceptions)
        XCTAssertEqual(days.days, Set(1...5))
    }
}
