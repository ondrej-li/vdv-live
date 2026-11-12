import Foundation

/// One file inside a line's archive entry: `Linky.txt`, `Spoje.txt`, `Zasspoje.txt`
/// and the rest of the JDF tables.
///
/// Kept as the file the archive actually holds rather than as rows: the point of
/// showing them is that a reader can see what was downloaded and what it says,
/// which is what turns "line not found" into something that can be answered.
struct TimetableSourceFile: Identifiable, Equatable, Sendable {
    /// Name as it appears inside the entry, `Linky.txt`.
    let name: String
    /// Size once inflated, which is what the file itself is worth.
    let bytes: Int

    var id: String { name }

    /// What the file is for, in a word, for the row that lists it.
    var purpose: String {
        switch name {
        case "Linky.txt": return String(localized: "Line")
        case "Spoje.txt": return String(localized: "Runs")
        case "Zasspoje.txt": return String(localized: "Stops of each run")
        case "Zastavky.txt": return String(localized: "Stops")
        case "Caskody.txt": return String(localized: "Calendar exceptions")
        case "Dopravci.txt": return String(localized: "Operators")
        case "Pevnykod.txt": return String(localized: "Fixed codes")
        case "VerzeJDF.txt": return String(localized: "Format version")
        case "Udaje.txt": return String(localized: "Header")
        case "Navaznosti.txt": return String(localized: "Connections")
        case "Zaslinky.txt": return String(localized: "Stop to line")
        default: return String(localized: "Table")
        }
    }
}

/// A line whose timetable the app can read right now, and where it came from.
struct DownloadedTimetable: Identifiable, Equatable, Sendable {
    let lineNumber: String
    let timetable: LineTimetable
    /// The archive entry the tables were read out of.
    let entryName: String
    /// True when that entry is a file cached for an earlier publication, which the
    /// current archive no longer holds under that name.
    let isFromEarlierArchive: Bool
    let sourceFiles: [TimetableSourceFile]

    var id: String { lineNumber }

    /// Line as a passenger writes it, `420`.
    var displayNumber: String { timetable.displayNumber }

    /// Runs in the order they leave, which is the order a reader scans them in.
    var runs: [ScheduledRun] { timetable.runs }

    /// Every stop any run of the line calls at, which is how long the line is.
    var stopCount: Int {
        Set(timetable.runs.flatMap { $0.calls.map(\.stopID) }).count
    }

    var totalSourceBytes: Int { sourceFiles.reduce(0) { $0 + $1.bytes } }

    /// The span the timetable covers, `04:35 – 17:55`.
    var spanText: String? {
        let times = timetable.runs.flatMap { $0.timedCalls.map(\.time.minutes) }
        guard let first = times.min(), let last = times.max() else { return nil }
        return "\(TimeOfDay(minutes: first).text) – \(TimeOfDay(minutes: last).text)"
    }

    /// The days the timetable is published for, as the archive writes them.
    var validityText: String? {
        let periods = timetable.validity
        guard !periods.isEmpty else { return nil }
        let from = periods.map(\.from.number).min().map(Self.day)
        let to = periods.compactMap(\.to?.number).max().map(Self.day)
        switch (from, to) {
        case let (from?, to?): return "\(from) – \(to)"
        case let (from?, nil): return String(format: String(localized: "from %@"), from)
        case let (nil, to?): return String(format: String(localized: "until %@"), to)
        default: return nil
        }
    }

    private static func day(_ number: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(number) * 86_400)
        return date.formatted(date: .numeric, time: .omitted)
    }
}
