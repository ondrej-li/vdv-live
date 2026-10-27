import Foundation

/// What the notification setup offers at each step: the lines that call at a stop,
/// and the services of one line that call there.
///
/// The choice is made of timetable facts rather than of free text: a notification is
/// about one run (`Spoj`) reaching one stop, so the service is picked from the runs
/// that actually call there, in the archive's own spelling of the stop. Kept apart
/// from the screen so that the steps can be tested without a phone.
enum ReminderSetup {
    /// A line that has at least one timed call at the chosen stop.
    struct Line: Identifiable, Hashable, Sendable {
        /// Archive line code, licence area included (`764421`).
        let lineNumber: String
        /// The number a passenger reads: `421`.
        let displayNumber: String
        let routeName: String
        /// The stop as this timetable names it, which is what a reminder stores.
        let stopName: String

        var id: String { lineNumber }
    }

    /// One run of a line that calls at the chosen stop.
    struct Service: Identifiable, Hashable, Sendable {
        /// `Spoj`: which run of the line.
        let serviceNumber: String
        /// The stop as this run names it, which is what a reminder stores.
        let stopName: String
        /// When the service leaves that stop, by the timetable.
        let departure: TimeOfDay
        /// Which days the run operates on, as the archive states them.
        let days: Weekdays

        var id: String { serviceNumber }
    }

    /// The weekly pattern a run's calendar states.
    ///
    /// Only what the header rules say: the dated exceptions (`Caskody.txt`) are a
    /// list of one-off dates, and a summary of them would be a paragraph rather than
    /// the "which days is this service" answer this screen offers.
    struct Weekdays: Hashable, Sendable {
        /// Monday is 1, Sunday is 7.
        let days: Set<Int>
        /// The run also operates on public holidays, whatever weekday they fall on.
        let includesHolidays: Bool
        /// The run has dated exceptions, so the pattern is not the whole story.
        let hasExceptions: Bool

        var isEveryDay: Bool { days.count == 7 }
    }

    /// The lines of `timetables` that call at `stop`, in passenger-number order.
    static func lines(in timetables: [LineTimetable], atStopNamed stop: String) -> [Line] {
        timetables.compactMap { timetable in
            let call = timetable.runs.lazy
                .compactMap { $0.call(matchingStopName: stop) }
                .first { $0.time != nil }
            guard let call else { return nil }
            return Line(lineNumber: timetable.lineNumber,
                        displayNumber: timetable.displayNumber,
                        routeName: timetable.routeName,
                        stopName: call.stopName)
        }
        .sorted {
            $0.displayNumber.localizedStandardCompare($1.displayNumber) == .orderedAscending
        }
    }

    /// The runs of `timetable` that call at `stop`, by run number.
    static func services(in timetable: LineTimetable, atStopNamed stop: String) -> [Service] {
        timetable.runs.compactMap { run in
            guard let call = run.call(matchingStopName: stop), let departure = call.time else {
                return nil
            }
            return Service(serviceNumber: run.serviceNumber,
                           stopName: call.stopName,
                           departure: departure,
                           days: weekdays(from: run.calendar))
        }
        .sorted {
            $0.serviceNumber.compare($1.serviceNumber, options: .numeric) == .orderedAscending
        }
    }

    /// The days a run's calendar states, before any dated exception is applied.
    ///
    /// A run with no header rule at all is the archive saying nothing, which every
    /// other part of the app reads as "runs whenever its times fit": every day.
    static func weekdays(from calendar: RunCalendar) -> Weekdays {
        let days: Set<Int>
        if calendar.rules.isEmpty {
            days = Set(1...7)
        } else {
            days = calendar.rules.reduce(into: Set<Int>()) { result, rule in
                switch rule {
                case .weekdays:
                    result.formUnion(1...5)
                case .sundaysAndHolidays:
                    result.insert(7)
                case .weekday(let weekday):
                    result.insert(weekday)
                }
            }
        }
        return Weekdays(days: days,
                        includesHolidays: calendar.rules.contains(.sundaysAndHolidays),
                        hasExceptions: !calendar.exceptions.isEmpty)
    }
}
