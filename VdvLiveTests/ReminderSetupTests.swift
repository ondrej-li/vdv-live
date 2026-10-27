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

    /// A line runs both ways, and its runs are numbered in one sequence, so the two
    /// directions have to be told apart by where they go.
    func testServicesCarryTheDirectionTheyRunIn() {
        let outbound = ScheduledRun(serviceNumber: "1", calls: [
            call(1, "Telč,,aut.nádr.", at: 7 * 60),
            call(2, "Třešť,,nám.", at: 7 * 60 + 25),
            call(3, "Brtnice", at: 7 * 60 + 50)
        ])
        let inbound = ScheduledRun(serviceNumber: "2", calls: [
            call(1, "Brtnice", at: 8 * 60),
            call(2, "Třešť,,nám.", at: 8 * 60 + 25),
            call(3, "Telč,,aut.nádr.", at: 8 * 60 + 50)
        ])
        let line = timetable(lineNumber: "764421", displayNumber: "421", runs: [outbound, inbound])

        let services = ReminderSetup.services(in: line, atStopNamed: "Třešť,nám.")

        XCTAssertEqual(services.map(\.serviceNumber), ["1", "2"])
        XCTAssertEqual(services[0].origin, "Telč,,aut.nádr.")
        XCTAssertEqual(services[0].destination, "Brtnice")
        XCTAssertEqual(services[1].origin, "Brtnice")
        XCTAssertEqual(services[1].destination, "Telč,,aut.nádr.")
        XCTAssertNotEqual(services[0].origin, services[1].origin,
                          "the two directions must not look the same")
    }

    /// The run goes on past the chosen stop, so the direction is the whole run's.
    func testDirectionIsTheWholeRunNotTheStop() {
        let line = timetable(
            lineNumber: "764421",
            displayNumber: "421",
            runs: [ScheduledRun(serviceNumber: "5", calls: [
                call(1, "Start", at: 6 * 60),
                call(2, "Zastávka", at: 6 * 60 + 10),
                call(3, "End", at: 6 * 60 + 30)
            ])]
        )

        let service = ReminderSetup.services(in: line, atStopNamed: "Zastávka").first

        XCTAssertEqual(service?.origin, "Start")
        XCTAssertEqual(service?.destination, "End")
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
