import Foundation

/// Works out which lines the timetable says are out, so the map can show the ones
/// the feed has gone quiet about.
///
/// Two steps, split because they change at different rates: a ``Schedule`` is read
/// out of the timetables once, when coverage changes, and then each payload only
/// has to compare it against the clock and the lines the feed reports. Without the
/// split every refresh would rebuild the same few hundred thousand call times.
enum ExpectedServices {
    /// How far outside its first and last call a run still counts as out.
    ///
    /// The window is the times the archive prints, and a bus leaves its first stop
    /// a minute or two after them; without slack a line would blink out at each end
    /// of the day. Wide enough to survive a late arrival, narrow enough not to
    /// claim a run that finished half an hour ago.
    static let defaultGraceMinutes = 10

    /// Timetables are Czech, so the day and the minute are read in Prague time
    /// whatever the phone is set to.
    static let regionTimeZone = TimeZone(identifier: "Europe/Prague") ?? .current

    private static let minutesInDay = 24 * 60

    // MARK: - The timetable, reduced to what the question needs

    /// Lines with the runs that can be placed in a day.
    ///
    /// A run with no times at all, or with times running backwards, has nowhere to
    /// be, so it is left out here rather than reconsidered on every payload.
    struct Schedule: Sendable {
        struct Line: Sendable {
            let lineNumber: String
            let runs: [Run]
        }

        struct Run: Sendable {
            let serviceNumber: String
            let validity: [ValidityPeriod]
            let firstMinute: Int
            let lastMinute: Int
            let calls: [TimedCall]

            func operates(on day: ServiceDay) -> Bool {
                validity.covers(day)
            }
        }

        struct TimedCall: Sendable {
            let stopName: String
            let time: TimeOfDay
        }

        var lines: [Line] = []
    }

    static func schedule(for timetables: [LineTimetable]) -> Schedule {
        Schedule(lines: timetables.map { timetable in
            Schedule.Line(
                lineNumber: timetable.lineNumber,
                runs: timetable.runs.compactMap { run in
                    let timed = run.timedCalls
                    guard let first = timed.first?.time, let last = timed.last?.time,
                          first <= last else { return nil }
                    return Schedule.Run(
                        serviceNumber: run.serviceNumber,
                        validity: run.validity,
                        firstMinute: first.minutes,
                        lastMinute: last.minutes,
                        calls: timed.map {
                            Schedule.TimedCall(stopName: $0.call.stopName, time: $0.time)
                        }
                    )
                }
            )
        })
    }

    // MARK: - Which of them are out

    /// One service per line that should be out at `now` and is not reported.
    ///
    /// - Parameters:
    ///   - schedule: the timetables at hand. A line not in here is simply not known
    ///     about, which is what an app without the archive has.
    ///   - reportingLines: line numbers the feed is reporting, in the same form as
    ///     ``LineTimetable/lineNumber``.
    ///   - stopPositions: where the stops are, as far as the app knows.
    static func services(
        in schedule: Schedule,
        reportingLines: Set<String>,
        now: Date,
        timeZone: TimeZone = regionTimeZone,
        stopPositions: StopPositions,
        graceMinutes: Int = defaultGraceMinutes
    ) -> [ExpectedService] {
        let day = ServiceDay(date: now, in: timeZone)
        let minute = minuteOfDay(for: now, in: timeZone)

        let services = schedule.lines.compactMap { line -> ExpectedService? in
            // A line the feed is reporting is not missing, whatever its runs say.
            guard !reportingLines.contains(line.lineNumber) else { return nil }
            return service(
                for: line,
                atMinute: minute,
                on: day,
                stopPositions: stopPositions,
                graceMinutes: graceMinutes
            )
        }
        return services.sorted { lhs, rhs in
            lhs.displayLine.compare(rhs.displayLine, options: .numeric) == .orderedAscending
        }
    }

    /// One service per line that should be out, straight from timetables.
    ///
    /// Builds the schedule on the way, which is what a caller with no schedule to
    /// keep wants.
    static func services(
        in timetables: [LineTimetable],
        reportingLines: Set<String>,
        now: Date,
        timeZone: TimeZone = regionTimeZone,
        stopPositions: StopPositions,
        graceMinutes: Int = defaultGraceMinutes
    ) -> [ExpectedService] {
        services(
            in: schedule(for: timetables),
            reportingLines: reportingLines,
            now: now,
            timeZone: timeZone,
            stopPositions: stopPositions,
            graceMinutes: graceMinutes
        )
    }

    /// The one service of a line: the run whose nearest call is nearest to now.
    ///
    /// A line usually has several runs on the road at once - a half-hourly service
    /// with forty-minute journeys has two. One marker per line is what the map can
    /// carry without turning a gap into a crowd, and the run closest to now is the
    /// one whose position is least stale.
    private static func service(
        for line: Schedule.Line,
        atMinute minute: Int,
        on day: ServiceDay,
        stopPositions: StopPositions,
        graceMinutes: Int
    ) -> ExpectedService? {
        var best: (run: Schedule.Run, call: Schedule.TimedCall, distance: Int)?

        for run in line.runs {
            guard run.operates(on: day) else { continue }
            // A night run is printed past midnight (`00:20` becomes 24:20 in the
            // archive's minutes), so the same clock minute has to be tried on the
            // day the run belongs to as well as on the one now falls in.
            for offset in [0, minutesInDay] {
                let nowMinute = minute + offset
                guard nowMinute >= run.firstMinute - graceMinutes,
                      nowMinute <= run.lastMinute + graceMinutes else { continue }
                guard let nearest = run.calls.min(by: { lhs, rhs in
                    abs(lhs.time.minutes - nowMinute) < abs(rhs.time.minutes - nowMinute)
                }) else { continue }
                let distance = abs(nearest.time.minutes - nowMinute)
                if let best, best.distance <= distance { continue }
                best = (run, nearest, distance)
            }
        }

        // No position means no marker: a service drawn at a stop we cannot place
        // would be a position the app invented.
        guard let best, let position = stopPositions.position(forStopNamed: best.call.stopName) else {
            return nil
        }
        return ExpectedService(
            lineNumber: line.lineNumber,
            serviceNumber: best.run.serviceNumber,
            stopName: best.call.stopName,
            latitude: position.latitude,
            longitude: position.longitude,
            scheduledTime: best.call.time
        )
    }

    /// Minutes after midnight at `date`, in the timetable's own time zone.
    static func minuteOfDay(for date: Date, in timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
