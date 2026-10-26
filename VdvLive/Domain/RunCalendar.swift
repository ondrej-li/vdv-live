import Foundation

/// Which days a JDF run operates on, in the archive's own vocabulary.
///
/// Two separate things decide it, and the archive keeps them in two files:
///
/// - **Attributes** (`Spoje.txt` → `Pevnykod.txt`): `X` for a working-day service,
///   `+` for a Sunday service that also runs on holidays, or a single digit 1-7 for
///   one weekday. These are what a printed timetable shows in its header.
/// - **Exceptions** (`Caskody.txt`): dated rules - "does not run 22.12.-2.1.",
///   "runs only 9.3.-15.3.", "runs in odd weeks". These are the footnotes.
///
/// The evaluation order is the one the published JDF-to-GTFS converters use, and it
/// is the order that makes the footnotes win over the header, which is how a
/// passenger reads them.
struct RunCalendar: Hashable, Sendable {
    /// The header rule of a run.
    enum Rule: Hashable, Sendable {
        /// `X`: Monday to Friday, except on a public holiday.
        case weekdays
        /// `+`: Sundays, and every public holiday whatever day it falls on.
        case sundaysAndHolidays
        /// `1`-`7`, Monday first: that one weekday, holidays included.
        case weekday(Int)
    }

    /// A dated rule from `Caskody.txt`.
    struct Exception: Hashable, Sendable {
        /// The `Typ časového kódu` column.
        enum Kind: Hashable, Sendable {
            case service           // 1: jede
            case serviceAlso       // 2: jede také
            case serviceOnly       // 3: jede jen
            case noService         // 4: nejede
            case oddWeeks          // 5: jede jen v lichých týdnech
            case evenWeeks         // 6: jede jen v sudých týdnech
            case oddWeeksFromTo    // 7
            case evenWeeksFromTo   // 8
        }

        let kind: Kind
        let from: ServiceDay
        /// `nil` when the archive left the end open, meaning that single day.
        let to: ServiceDay?

        func contains(_ day: ServiceDay) -> Bool {
            guard day >= from else { return false }
            guard let to else { return day == from }
            return day <= to
        }
    }

    var rules: Set<Rule> = []
    var exceptions: [Exception] = []

    /// A run the archive said nothing about: it runs whenever its times fit.
    static let everyDay = RunCalendar()

    /// Whether the run operates on `day`, holidays and exceptions included.
    func operates(on day: ServiceDay) -> Bool {
        let kinds = Set(exceptions.filter { $0.contains(day) }.map(\.kind))
        let hasServiceOnly = exceptions.contains { $0.kind == .serviceOnly }
        let hasService = exceptions.contains { $0.kind == .service }
        let holiday = CzechHolidays.isHoliday(day)
        let weekday = day.weekday

        // The footnotes first, in the order a reader resolves them: "goes only"
        // beats everything, then "does not go", then "also goes", then the
        // parity rules, then a plain "goes" rule that does not cover this day.
        if kinds.contains(.serviceOnly) { return true }
        if hasServiceOnly { return false }
        if kinds.contains(.noService) { return false }
        if kinds.contains(.serviceAlso) { return true }

        let isOddWeek = day.isoWeek % 2 == 1
        if (kinds.contains(.oddWeeks) || kinds.contains(.oddWeeksFromTo)), !isOddWeek { return false }
        if (kinds.contains(.evenWeeks) || kinds.contains(.evenWeeksFromTo)), isOddWeek { return false }

        if !kinds.contains(.service), hasService { return false }

        // Then the header.
        if rules.contains(.sundaysAndHolidays), holiday || weekday == 7 { return true }
        if rules.contains(.weekdays), !holiday, weekday <= 5 { return true }
        if rules.contains(.weekday(weekday)) { return true }

        // No calendar attribute at all is not "never": it is "the archive did not
        // say", and a run nobody ruled out is a run that runs.
        return rules.isEmpty
    }

    /// Reads a `Pevnykod` symbol into a rule. Symbols that say something other
    /// than which days a run operates (`@` accessibility, `O` bicycles, the call
    /// marks `x`, `<`, `|`) are not calendar rules and come back `nil`.
    static func rule(forSymbol symbol: String) -> Rule? {
        switch symbol {
        case "X": return .weekdays
        case "+": return .sundaysAndHolidays
        case "1", "2", "3", "4", "5", "6", "7":
            guard let number = Int(symbol) else { return nil }
            return .weekday(number)
        default: return nil
        }
    }
}
