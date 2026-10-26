import XCTest
@testable import VdvLive

final class ReminderScheduleTests: XCTestCase {
    private let prague = ReminderSchedule.timeZone

    private func date(_ text: String, hour: Int = 6, minute: Int = 0) throws -> Date {
        let day = try XCTUnwrap(ServiceDay(archiveText: text))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = prague
        let parts = day.components
        return try XCTUnwrap(calendar.date(from: DateComponents(year: parts.year,
                                                                month: parts.month,
                                                                day: parts.day,
                                                                hour: hour,
                                                                minute: minute)))
    }

    /// One line with one run, calling at `stop` at `departure` (minutes after
    /// midnight), published for `periods`.
    private func timetable(departure: Int,
                          rules: Set<RunCalendar.Rule> = [.weekdays],
                          exceptions: [RunCalendar.Exception] = [],
                          periods: [ValidityPeriod] = []) -> LineTimetable {
        let run = ScheduledRun(
            serviceNumber: "9",
            calls: [
                ScheduledCall(order: 1, stopID: "1", stopName: "Jinde",
                              arrival: nil, departure: TimeOfDay(minutes: departure - 20),
                              distanceKilometres: 0, isServed: true),
                ScheduledCall(order: 2, stopID: "2", stopName: "Zašovice,Nová Brtnice",
                              arrival: nil, departure: TimeOfDay(minutes: departure),
                              distanceKilometres: 4, isServed: true)
            ],
            validity: periods,
            calendar: RunCalendar(rules: rules, exceptions: exceptions)
        )
        return LineTimetable(lineNumber: "764421",
                             displayNumber: "421",
                             routeName: "Test",
                             operatorName: nil,
                             runs: [run],
                             validity: periods)
    }

    private func reminder(lead: Int = 10, excluded: Set<Int> = []) -> Reminder {
        Reminder(lineNumber: "764421",
                 serviceNumber: "9",
                 stopName: "Zašovice,Nová Brtnice",
                 leadMinutes: lead,
                 excludedWeekdays: excluded)
    }

    /// A working-day service, a week ahead from a Tuesday: Monday to Friday only.
    func testAWeeksWorthOfWorkingDays() throws {
        let line = timetable(departure: 7 * 60 + 42)
        let occurrences = ReminderSchedule.occurrences(
            for: reminder(),
            in: line,
            now: try date("20102026"),
            horizonDays: 7
        )

        XCTAssertEqual(occurrences.map { $0.day.components.day }, [20, 21, 22, 23, 26, 27])
        XCTAssertEqual(occurrences.first?.departure, TimeOfDay(minutes: 7 * 60 + 42))
    }

    /// The lead moves the notification, not the bus.
    func testTheLeadMovesTheNotification() throws {
        let line = timetable(departure: 7 * 60 + 42)
        let occurrences = ReminderSchedule.occurrences(
            for: reminder(lead: 15),
            in: line,
            now: try date("20102026"),
            horizonDays: 1
        )

        let fire = try XCTUnwrap(occurrences.first?.fireAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = prague
        XCTAssertEqual(calendar.component(.hour, from: fire), 7)
        XCTAssertEqual(calendar.component(.minute, from: fire), 27)
    }

    /// A user who does not want Mondays does not get Mondays.
    func testExcludedWeekdaysAreLeftOut() throws {
        let line = timetable(departure: 7 * 60 + 42)
        let occurrences = ReminderSchedule.occurrences(
            for: reminder(excluded: [2]),   // Tuesday
            in: line,
            now: try date("20102026"),
            horizonDays: 7
        )

        // 27 October is a Tuesday too, so it goes as well.
        XCTAssertEqual(occurrences.map { $0.day.components.day }, [21, 22, 23, 26])
    }

    /// 28 October 2026 is a Wednesday holiday, and `X` does not run on it.
    func testHolidaysAreNotScheduled() throws {
        let line = timetable(departure: 7 * 60 + 42)
        let occurrences = ReminderSchedule.occurrences(
            for: reminder(),
            in: line,
            now: try date("20102026"),
            horizonDays: 8
        )

        XCTAssertFalse(occurrences.contains { $0.day.components.day == 28 })
    }

    /// The timetable's own end is the end of the schedule.
    func testStopsAtTheEndOfThePublishedPeriod() throws {
        let end = try XCTUnwrap(ServiceDay(archiveText: "21102026"))
        let line = timetable(departure: 7 * 60 + 42,
                             periods: [ValidityPeriod(from: try XCTUnwrap(ServiceDay(archiveText: "01102026")),
                                                      to: end)])
        let occurrences = ReminderSchedule.occurrences(
            for: reminder(),
            in: line,
            now: try date("20102026"),
            horizonDays: 21
        )

        XCTAssertEqual(occurrences.map { $0.day.components.day }, [20, 21])
    }

    /// When the archive leaves the end open, the schedule stops at the timetable
    /// change: the day before the second Sunday of December.
    func testStopsAtTheDecemberChangeWhenThePeriodIsOpen() throws {
        let line = timetable(departure: 7 * 60 + 42,
                             periods: [ValidityPeriod(from: try XCTUnwrap(ServiceDay(archiveText: "01102026")),
                                                      to: nil)])
        let last = ReminderSchedule.endOfPeriod(
            for: line,
            from: try XCTUnwrap(ServiceDay(archiveText: "01122026")),
            horizonDays: 21
        )

        // 13 December 2026 is the second Sunday; the period ends the day before.
        XCTAssertEqual(last, ServiceDay(archiveText: "12122026"))
    }

    func testTheSecondSundayOfDecemberIsMeasured() {
        XCTAssertEqual(ReminderSchedule.secondSundayOfDecember(2025),
                       ServiceDay(archiveText: "14122025"))
        XCTAssertEqual(ReminderSchedule.secondSundayOfDecember(2026),
                       ServiceDay(archiveText: "13122026"))
    }

    /// A bus that has already gone is not a reminder.
    func testSkipsTodaysDepartureOnceItHasPassed() throws {
        let line = timetable(departure: 7 * 60 + 42)
        let occurrences = ReminderSchedule.occurrences(
            for: reminder(),
            in: line,
            now: try date("20102026", hour: 8),
            horizonDays: 1
        )

        // Today's has gone; tomorrow's is still ahead.
        XCTAssertEqual(occurrences.map { $0.day.components.day }, [21])
    }

    /// A stop the run does not call at schedules nothing, rather than throwing or
    /// silently using another stop.
    func testUnknownStopSchedulesNothing() throws {
        let line = timetable(departure: 7 * 60 + 42)
        let wrong = Reminder(lineNumber: "764421",
                             serviceNumber: "9",
                             stopName: "Nikde",
                             leadMinutes: 5)
        XCTAssertTrue(ReminderSchedule.occurrences(for: wrong,
                                                   in: line,
                                                   now: try date("20102026")).isEmpty)
    }

    func testUnknownRunSchedulesNothing() throws {
        let line = timetable(departure: 7 * 60 + 42)
        let wrong = Reminder(lineNumber: "764421",
                             serviceNumber: "99",
                             stopName: "Zašovice,Nová Brtnice",
                             leadMinutes: 5)
        XCTAssertTrue(ReminderSchedule.occurrences(for: wrong,
                                                   in: line,
                                                   now: try date("20102026")).isEmpty)
    }
}
