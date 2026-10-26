import Foundation

/// Turns a reminder into the moments a notification should arrive.
///
/// Everything here is arithmetic on the timetable the app already holds: the run's
/// own calendar (weekdays, public holidays, the archive's exceptions), the stop's
/// time within it, and the lead the user asked for. No network, so the whole
/// question is testable without a phone.
enum ReminderSchedule {
    /// One fire time: the departure it warns about and when to warn.
    struct Occurrence: Hashable, Sendable {
        /// The day the service runs.
        let day: ServiceDay
        /// The departure from the reminder's stop, by the timetable.
        let departure: TimeOfDay
        /// When the notification should arrive.
        let fireAt: Date
        /// The same moment as the notification's calendar components, so a
        /// scheduled request does not depend on the device's time zone at the
        /// time it fires.
        var components: DateComponents {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = ReminderSchedule.timeZone
            return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
        }
    }

    /// Timetables are Czech, so their times are read in Prague whatever the phone
    /// is set to - the same rule the rest of the app follows.
    static let timeZone = TimeZone(identifier: "Europe/Prague") ?? .current

    /// Every occurrence of `reminder` that still lies ahead, latest last.
    ///
    /// - Parameters:
    ///   - now: the moment the schedule is built; anything at or before it is left
    ///     out, because a notification for a bus that has gone is noise.
    ///   - horizonDays: how far ahead to look, capped by the timetable's own end.
    static func occurrences(
        for reminder: Reminder,
        in timetable: LineTimetable,
        now: Date,
        horizonDays: Int = Reminder.horizonDays
    ) -> [Occurrence] {
        guard let run = timetable.run(serviceNumber: reminder.serviceNumber),
              let call = run.call(matchingStopName: reminder.stopName),
              let departure = call.time else { return [] }

        let today = ServiceDay(date: now, in: timeZone)
        let lastDay = endOfPeriod(for: timetable, from: today, horizonDays: horizonDays)
        guard lastDay >= today else { return [] }

        var occurrences: [Occurrence] = []
        for offset in 0...today.distance(to: lastDay) {
            let day = today.adding(days: offset)
            guard reminder.isWanted(on: day), run.operates(on: day) else { continue }
            guard let fireAt = fireDate(day: day,
                                        departure: departure,
                                        leadMinutes: reminder.leadMinutes),
                  fireAt > now else { continue }
            occurrences.append(Occurrence(day: day, departure: departure, fireAt: fireAt))
        }
        return occurrences
    }

    /// The last day worth scheduling for.
    ///
    /// Usually the timetable's own period ends there. When the archive left the end
    /// open, the answer is the day before the second Sunday of December: Czech
    /// timetables change on that Sunday, and every line in a sample of the October
    /// 2026 archive that does state an end states exactly that day (`12122026`).
    static func endOfPeriod(for timetable: LineTimetable,
                            from today: ServiceDay,
                            horizonDays: Int) -> ServiceDay {
        let horizon = today.adding(days: horizonDays)
        let stated = timetable.validity.compactMap(\.to).min()
        let end = stated ?? nextTimetableChange(after: today).adding(days: -1)
        return min(horizon, end)
    }

    /// The second Sunday of the next December on or after `day`.
    static func nextTimetableChange(after day: ServiceDay) -> ServiceDay {
        let year = day.components.year
        let thisYear = secondSundayOfDecember(year)
        return day <= thisYear ? thisYear : secondSundayOfDecember(year + 1)
    }

    static func secondSundayOfDecember(_ year: Int) -> ServiceDay {
        let firstOfDecember = ServiceDay(year: year, month: 12, day: 1)
        // Weekday 7 is Sunday; the first Sunday is 0-6 days after the 1st.
        let offsetToSunday = (7 - firstOfDecember.weekday) % 7
        return firstOfDecember.adding(days: offsetToSunday + 7)
    }

    /// The same clock time on `day`, in the timetables' time zone, moved back by
    /// the lead.
    static func fireDate(day: ServiceDay,
                         departure: TimeOfDay,
                         leadMinutes: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = day.components
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        components.day = parts.day
        components.hour = (departure.minutes / 60) % 24
        components.minute = departure.minutes % 60
        guard let departureDate = calendar.date(from: components) else { return nil }
        return departureDate.addingTimeInterval(TimeInterval(-leadMinutes * 60))
    }
}
