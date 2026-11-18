import Foundation

/// Time of day as printed in a timetable, counted from midnight.
struct TimeOfDay: Hashable, Comparable, Sendable {
    /// Minutes after midnight. Timetables run past midnight, so this can exceed
    /// 24 hours for a night service.
    let minutes: Int

    init(minutes: Int) {
        self.minutes = minutes
    }

    /// `1432` as JDF writes it, or `nil` when the field is empty or `--`.
    init?(clock: String) {
        let digits = clock.trimmingCharacters(in: .whitespaces)
        guard digits.count == 4, digits.allSatisfy(\.isNumber),
              let value = Int(digits) else { return nil }
        let hour = value / 100
        let minute = value % 100
        guard hour < 48, minute < 60 else { return nil }
        self.minutes = hour * 60 + minute
    }

    /// `14:32`, the way the timetable prints it.
    var text: String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    /// The same time shifted by a delay, which can be negative on an early bus.
    func shifted(byMinutes delay: Int) -> TimeOfDay {
        TimeOfDay(minutes: max(minutes + delay, 0))
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutes < rhs.minutes
    }
}

/// One scheduled call of a run.
struct ScheduledCall: Hashable, Identifiable, Sendable {
    /// Place in the run, as published.
    let order: Int
    let stopID: String
    /// "Telč,aut.nádr." - municipality and part, the way the feed writes it.
    let stopName: String
    let arrival: TimeOfDay?
    let departure: TimeOfDay?
    /// Distance from the start of the run, in kilometres.
    let distanceKilometres: Int?
    /// Whether this run calls at the stop at all.
    ///
    /// A service does not have to serve every stop of its line: some runs of a
    /// line take a different way round, and the archive marks the stops they skip
    /// with a symbol in the time columns rather than a time. For line 337 that is
    /// Petrovice, served by two runs out of twelve and marked by the other ten.
    let isServed: Bool

    var id: Int { order }

    /// The time a passenger cares about: the departure, or the arrival at the
    /// end of the line. JDF fills in one of the two at most.
    var time: TimeOfDay? { departure ?? arrival }

    /// Whether a time can be quoted for this call at all.
    var hasTime: Bool { time != nil }

    /// The same time, late by `delayMinutes`.
    func time(lateByMinutes delayMinutes: Int) -> TimeOfDay? {
        time?.shifted(byMinutes: delayMinutes)
    }
}

/// One run of a line: the vehicles the feed reports as `Spoj`.
struct ScheduledRun: Hashable, Identifiable, Sendable {
    /// JDF run number, the same number the feed reports as `Spoj`.
    let serviceNumber: String
    /// Calls in travel order.
    let calls: [ScheduledCall]

    var id: String { serviceNumber }

    var lastCall: ScheduledCall? { calls.last }

    /// The calls of one run, in the order the vehicle calls at them.
    ///
    /// JDF numbers the stops along the *line*, not along the run, so a run
    /// travelling the other way counts up against the direction it is going in
    /// and its times run backwards against that numbering. That is the case for
    /// about half the runs in the published archive, and taken at face value it
    /// prints those timetables in reverse.
    ///
    /// The direction is decided from the times, while the numbering still says
    /// where each call sits within the run - which is what keeps a request stop,
    /// whose time JDF does not print at all, in its place instead of at one end.
    static func inTravelOrder(_ calls: [ScheduledCall]) -> [ScheduledCall] {
        let ordered = calls.sorted { $0.order < $1.order }
        let times = ordered.compactMap(\.time)
        guard let first = times.first, let last = times.last, first > last else {
            return ordered
        }
        return ordered.reversed()
    }

    /// The call of this run at a stop the feed reported, matched the relaxed way.
    func call(matchingStopName name: String) -> ScheduledCall? {
        LineTimetable.call(matchingStopName: name, in: calls)
    }
}

/// A line's published timetable, read out of the official JDF export.
struct LineTimetable: Hashable, Sendable {
    /// CIS line number, licence area prefix included: `764337`.
    let lineNumber: String
    /// Passenger facing number: `337`.
    let displayNumber: String
    /// "Třešť-Brtnice-Okříšky-Radonín".
    let routeName: String
    let operatorName: String?
    let runs: [ScheduledRun]

    var isEmpty: Bool { runs.isEmpty }

    /// The run with the given JDF run number, which is what the feed calls `Spoj`.
    func run(serviceNumber: String) -> ScheduledRun? {
        runs.first { $0.serviceNumber == serviceNumber }
    }

    /// The run a vehicle is on, given the number from its info window.
    func run(serviceNumber: String?) -> ScheduledRun? {
        guard let serviceNumber else { return nil }
        return run(serviceNumber: serviceNumber)
    }

    /// Which call of the run a stop name belongs to.
    ///
    /// The feed reports the stop a vehicle was last seen at, so this is what
    /// turns "somewhere on this line" into "call 7 of 23".
    func call(matchingStopName name: String) -> ScheduledCall? {
        LineTimetable.call(matchingStopName: name, in: runs.flatMap(\.calls))
    }

    /// The call whose stop the feed reported, or `nil` when nothing on the line
    /// comes close.
    static func call(matchingStopName name: String, in calls: [ScheduledCall]) -> ScheduledCall? {
        let wanted = comparableStopName(name)
        let matches = calls.compactMap { stopMatch(wanted, $0) }
        guard let best = matches.map(\.score).max() else { return nil }
        // The first of the best: on a line that calls at the same stop twice, the
        // earlier call is the one the vehicle has just reached.
        return matches.first { $0.score == best }?.call
    }

    /// How well a call's stop name matches the one the feed reported.
    ///
    /// The feed names stops in more detail than the archive does - it reports
    /// "Stonařov,Sokolíčko,rozc." where the timetable has "Stonařov,Sokolíčko" -
    /// so a name that starts with the whole of the other is the same stop, and the
    /// longest such match wins. Scoring by length is what keeps the plain
    /// "Stonařov" stop from answering when the vehicle is at the one beyond it.
    private static func stopMatch(
        _ wanted: String,
        _ call: ScheduledCall
    ) -> (call: ScheduledCall, score: Int)? {
        let name = comparableStopName(call.stopName)
        let (shorter, longer) = wanted.count <= name.count ? (wanted, name) : (name, wanted)
        guard shorter == longer || longer.hasPrefix(shorter + " ") else { return nil }
        return (call, shorter.count)
    }

    /// Stop names differ in small ways between the feed and the archive, so they
    /// are compared without case, diacritics, bracketed tariff suffixes or
    /// spaces.
    static func comparableStopName(_ name: String) -> String {
        var cleaned = name
        while let open = cleaned.firstIndex(of: "["), let close = cleaned[open...].firstIndex(of: "]") {
            cleaned.removeSubrange(open...close)
        }
        cleaned = cleaned.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return cleaned.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
