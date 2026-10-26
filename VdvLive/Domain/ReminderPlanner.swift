import Foundation

/// Decides which notifications the app asks the system to deliver, and what they
/// say.
///
/// This is the whole of the scheduling logic, and it is pure: reminders in,
/// notifications out. Everything that can be wrong about a reminder - a stop the run
/// does not call at, a holiday, an excluded Monday, a timetable that ends in
/// December - is decided here, where it can be tested without a phone.
enum ReminderPlanner {
    /// How many notifications to keep pending at once.
    ///
    /// iOS keeps the soonest ~64 pending requests per app and silently drops the
    /// rest, so this leaves room for the reminder closest to hand rather than
    /// handing the system a list longer than it will honour.
    static let pendingLimit = 60

    /// Every notification worth scheduling, soonest first.
    ///
    /// - Parameter timetables: by archive line number. A reminder whose line has no
    ///   timetable - not downloaded, or not in the archive - simply produces nothing;
    ///   it is not an error, and the screen says which lines are waiting.
    static func notifications(for reminders: [Reminder],
                              timetables: [String: LineTimetable],
                              now: Date,
                              limit: Int = pendingLimit) -> [PlannedNotification] {
        let planned = reminders.flatMap { reminder -> [(Date, PlannedNotification)] in
            guard let timetable = timetables[reminder.lineNumber] else { return [] }
            return ReminderSchedule.occurrences(for: reminder, in: timetable, now: now)
                .map { occurrence in
                    (occurrence.fireAt, notification(for: reminder,
                                                     occurrence: occurrence))
                }
        }

        return planned
            .sorted { $0.0 < $1.0 }
            .prefix(limit)
            .map(\.1)
    }

    static func notification(for reminder: Reminder,
                             occurrence: ReminderSchedule.Occurrence) -> PlannedNotification {
        let line = reminder.displayLineNumber
        let stop = occurrenceStopName(reminder)
        return PlannedNotification(
            identifier: "\(reminder.id.uuidString).\(occurrence.day.number)",
            fireAt: occurrence.components,
            title: String(format: String(localized: "Line %@ · service %@"), line, reminder.serviceNumber),
            body: String(format: String(localized: "%@ from %@"), occurrence.departure.text, stop),
            userInfo: [
                PlannedNotification.Key.line: reminder.lineNumber,
                PlannedNotification.Key.service: reminder.serviceNumber,
                PlannedNotification.Key.stop: reminder.stopName,
                PlannedNotification.Key.reminder: reminder.id.uuidString
            ]
        )
    }

    /// The stop as it is written to a person: the archive writes "Zašovice,Nová
    /// Brtnice", which reads better with a space after the comma.
    private static func occurrenceStopName(_ reminder: Reminder) -> String {
        reminder.stopName.replacingOccurrences(of: ",", with: ", ")
    }
}
