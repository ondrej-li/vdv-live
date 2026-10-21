import Foundation

/// One line leaving a stop, as the stop's board shows it.
///
/// The board is built from the timetables the app already holds plus the delays
/// the live feed reports: `scheduled` always comes from the timetable, and
/// `expected` only when a vehicle of that run is reporting, because a delay that
/// belongs to another run of the same line is not this row's business.
struct StopBoardEntry: Identifiable, Hashable, Sendable {
    /// The line as a passenger writes it, "410".
    let lineNumber: String
    /// The run within the line, which is the thing a delay is known for.
    let serviceNumber: String
    /// What the timetable says.
    let scheduled: TimeOfDay
    /// What the live feed makes of it, when a vehicle of this run is reporting.
    let expected: TimeOfDay?

    var id: String { "\(lineNumber)/\(serviceNumber)/\(scheduled.minutes)" }

    /// How late the row is, or nil while nothing is reporting for it - which is
    /// the "not departed yet" case, not "on time".
    var delayMinutes: Int? {
        guard let expected else { return nil }
        return expected.minutes - scheduled.minutes
    }

    var isOnTime: Bool { delayMinutes == 0 }
}

/// What a stop's board shows, and which departures belong on it.
///
/// The window reaches an hour back and three hours forward, but a late vehicle is
/// never dropped for being late: a service scheduled at 13:40 and running thirty
/// minutes behind belongs on a board read at 15:00, because its expected time,
/// 14:20, is still within the hour that has passed. So the test is applied to the
/// time the row will actually be read by - `expected` when it is known, `scheduled`
/// otherwise.
enum StopBoard {
    /// Minutes before now the board reaches.
    static let lookBackMinutes = 60
    /// Minutes after now the board reaches.
    static let lookAheadMinutes = 180

    /// The rows of the board at a stop, earliest first.
    ///
    /// - Parameters:
    ///   - stopName: the name the timetable uses, which is what `ScheduledCall`
    ///     carries - the same spelling the bundled stop table is keyed by.
    ///   - timetables: whatever the app holds for the lines that serve the stop.
    ///   - delays: minutes late, keyed by `"<line>/<run>"`; anything missing is
    ///     drawn as not departed yet.
    ///   - now: the minute the board is read at, so that the window is testable.
    static func entries(
        at stopName: String,
        in timetables: [LineTimetable],
        delays: [String: Int] = [:],
        now: TimeOfDay
    ) -> [StopBoardEntry] {
        var entries: [StopBoardEntry] = []

        for timetable in timetables {
            for run in timetable.runs {
                // The stop names come from two places - the bundled table and the
                // archive - so the line's own lenient matching is what decides
                // whether this run calls here at all.
                guard let call = run.call(matchingStopName: stopName),
                      let scheduled = call.time else { continue }

                let late = delays[delayKey(line: timetable.lineNumber, service: run.serviceNumber)]
                let expected = late.flatMap { call.time(lateByMinutes: $0) }
                let readAt = (expected ?? scheduled).minutes

                guard readAt >= now.minutes - lookBackMinutes,
                      readAt <= now.minutes + lookAheadMinutes else { continue }

                entries.append(
                    StopBoardEntry(
                        lineNumber: timetable.lineNumber,
                        serviceNumber: run.serviceNumber,
                        scheduled: scheduled,
                        expected: expected
                    )
                )
            }
        }

        return entries.sorted { first, second in
            let firstAt = (first.expected ?? first.scheduled).minutes
            let secondAt = (second.expected ?? second.scheduled).minutes
            if firstAt != secondAt { return firstAt < secondAt }
            if first.lineNumber != second.lineNumber { return first.lineNumber < second.lineNumber }
            return first.serviceNumber < second.serviceNumber
        }
    }

    /// The key a run's delay is looked up by.
    static func delayKey(line: String, service: String) -> String {
        "\(line)/\(service)"
    }
}
