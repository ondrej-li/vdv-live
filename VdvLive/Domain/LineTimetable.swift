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
    /// True for a stop the vehicle only serves on request. JDF writes `<` in the
    /// time columns instead of a time, so such a call has no time at all.
    let isOnRequest: Bool

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

    /// The call of this run at a stop the feed reported, matched the relaxed way.
    func call(matchingStopName name: String) -> ScheduledCall? {
        let wanted = LineTimetable.comparableStopName(name)
        return calls.first { LineTimetable.comparableStopName($0.stopName) == wanted }
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
        let wanted = LineTimetable.comparableStopName(name)
        return runs
            .flatMap(\.calls)
            .first { LineTimetable.comparableStopName($0.stopName) == wanted }
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
