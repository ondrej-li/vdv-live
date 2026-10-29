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
    /// Where this run ends, which is what a passenger reads a board for.
    ///
    /// The last stop of the run, not the line's route name: two runs of one line can
    /// go opposite ways, and "Třešť-Brtnice-Okříšky-Radonín" tells nobody which end
    /// the bus in front of them is heading for.
    let destination: String?

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
    /// How long after a run's last call a vehicle still counts as being on that run.
    ///
    /// Long enough to keep a badly late service on the board, short enough that the line's
    /// next service - which has not left the depot - does not inherit its delay.
    static let delayTailMinutes = 120

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
        var rows: [Row] = []

        for timetable in timetables {
            for run in timetable.runs {
                // The stop names come from two places - the bundled table and the
                // archive - so the line's own lenient matching is what decides
                // whether this run calls here at all.
                guard let call = run.call(matchingStopName: stopName),
                      let scheduled = call.time else { continue }

                rows.append(
                    Row(
                        lineNumber: timetable.lineNumber,
                        serviceNumber: run.serviceNumber,
                        scheduled: scheduled,
                        call: call,
                        destination: run.calls.last?.stopName,
                        isUnderWay: Self.isUnderWay(run, at: now),
                        // Only a delay the feed reports for this very run is this row's
                        // own business.
                        delay: delays[delayKey(line: timetable.lineNumber,
                                               service: run.serviceNumber)]
                    )
                )
            }
        }

        Self.lendLineDelays(to: &rows, delays: delays, now: now)

        return rows
            .filter {
                $0.readAt >= now.minutes - lookBackMinutes
                    && $0.readAt <= now.minutes + lookAheadMinutes
            }
            .map(\.entry)
            .sorted { first, second in
                let firstAt = (first.expected ?? first.scheduled).minutes
                let secondAt = (second.expected ?? second.scheduled).minutes
                if firstAt != secondAt { return firstAt < secondAt }
                if first.lineNumber != second.lineNumber { return first.lineNumber < second.lineNumber }
                return first.serviceNumber < second.serviceNumber
            }
    }

    /// A line's delay, given to the one row the vehicle reporting it can be on.
    ///
    /// The positions feed names the line but not the run, so a delay is the line's rather
    /// than a run's. Lending it to every service of the line put delays on departures that
    /// had not left yet - the bug this fixes - so it goes to the single nearest row of a
    /// run that is actually under way, and to nothing else.
    private static func lendLineDelays(to rows: inout [Row],
                                       delays: [String: Int],
                                       now: TimeOfDay) {
        var owner: [String: Int] = [:]

        for index in rows.indices {
            let row = rows[index]
            guard row.delay == nil, row.isUnderWay, delays[row.lineNumber] != nil else { continue }
            guard let current = owner[row.lineNumber] else {
                owner[row.lineNumber] = index
                continue
            }
            if Self.distance(rows[current].scheduled, now) > Self.distance(row.scheduled, now) {
                owner[row.lineNumber] = index
            }
        }

        for (line, index) in owner {
            rows[index].delay = delays[line]
        }
    }

    /// Whether a run is on the road, near enough for a vehicle's delay to be its own.
    private static func isUnderWay(_ run: ScheduledRun, at now: TimeOfDay) -> Bool {
        let times = run.calls.compactMap(\.time).map(\.minutes)
        guard let first = times.min(), let last = times.max() else { return false }
        return now.minutes >= first && now.minutes <= last + delayTailMinutes
    }

    private static func distance(_ time: TimeOfDay, _ now: TimeOfDay) -> Int {
        abs(time.minutes - now.minutes)
    }

    /// A row before it becomes a board entry: the call is kept so that the delay, once it
    /// is known, can shift the time the way the timetable shifts it.
    private struct Row {
        let lineNumber: String
        let serviceNumber: String
        let scheduled: TimeOfDay
        let call: ScheduledCall
        let destination: String?
        let isUnderWay: Bool
        var delay: Int?

        var expected: TimeOfDay? { delay.flatMap { call.time(lateByMinutes: $0) } }
        var readAt: Int { (expected ?? scheduled).minutes }

        var entry: StopBoardEntry {
            StopBoardEntry(lineNumber: lineNumber,
                           serviceNumber: serviceNumber,
                           scheduled: scheduled,
                           expected: expected,
                           destination: destination)
        }
    }

    /// The key a run's delay is looked up by.
    static func delayKey(line: String, service: String) -> String {
        "\(line)/\(service)"
    }
}
