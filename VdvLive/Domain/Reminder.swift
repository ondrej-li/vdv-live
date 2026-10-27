import Foundation

/// A standing request to be warned before a particular service reaches a stop.
///
/// The service is the thing, not the line: "421 - 9" is run 9 of line 421, which
/// is what `Spoj` means in the archive and what the stop board already shows. A
/// reminder about a line would fire for every bus of it.
struct Reminder: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    /// Archive line code, licence area included (`764421`), because that is what
    /// the timetable lookup is filed under.
    let lineNumber: String
    /// `Spoj`: which run of the line.
    let serviceNumber: String
    /// The stop as the timetables name it ("Zašovice,Nová Brtnice").
    let stopName: String
    /// How long before the departure the notification arrives.
    let leadMinutes: Int
    /// Days of the week the user does not want it: 1 is Monday, 7 is Sunday.
    ///
    /// Excluding a day the service does not run on changes nothing; excluding one
    /// it does is how "not on Mondays, I am not in the office" is said.
    let excludedWeekdays: Set<Int>

    init(id: UUID = UUID(),
         lineNumber: String,
         serviceNumber: String,
         stopName: String,
         leadMinutes: Int,
         excludedWeekdays: Set<Int> = []) {
        self.id = id
        self.lineNumber = lineNumber
        self.serviceNumber = serviceNumber
        self.stopName = stopName
        self.leadMinutes = leadMinutes
        self.excludedWeekdays = excludedWeekdays
    }

    /// The line the way a passenger writes it, licence area removed.
    var displayLineNumber: String { LineCode(raw: lineNumber).number }

    /// Whether the reminder is due on `day` at all, before the timetable is asked.
    func isWanted(on day: ServiceDay) -> Bool {
        !excludedWeekdays.contains(day.weekday)
    }

    /// Leads a reader is offered, in minutes.
    static let leadOptions = Array(stride(from: 5, through: 60, by: 5))

    /// How far ahead reminders are scheduled.
    ///
    /// iOS keeps only the soonest ~64 pending notifications per app, so this is a
    /// budget rather than a wish: three weeks of one daily service is about 21.
    static let horizonDays = 21
}
