import Foundation

/// Reads the JDF files of one line into a ``LineTimetable``.
///
/// JDF is the Czech timetable format: every row is a quoted, semicolon
/// terminated list of fields, the files are CP1250, and a line's package holds
/// one file per table. `docs/timetables.md` records where the column numbers
/// come from - they were read off the published data, not from a guess.
enum JDFTimetableParser {
    enum Failure: Error, Equatable {
        case missingFile(String)
        case notText(String)
        case noLine
    }

    /// Column layout of the tables this parser needs.
    private enum Column {
        static let lineNumber = 0

        enum Line {
            static let routeName = 1
            static let operatorID = 2
            /// The timetable period, as `DDMMYYYY`. The package says when it starts
            /// and, for the current one, when it ends - which is the day before the
            /// next timetable change.
            static let validityFrom = 13
            static let validityTo = 14
        }

        /// `Spoje.txt`: line, run, then up to ten fixed-code references.
        enum Trip {
            static let serviceNumber = 1
            static let firstAttribute = 2
            static let lastAttribute = 11
        }

        /// `Pevnykod.txt`: fixed code, then the symbol it stands for.
        enum FixedCode {
            static let code = 0
            static let symbol = 1
        }

        enum Operator {
            static let name = 2
        }

        enum Call {
            static let serviceNumber = 1
            static let order = 2
            static let stopID = 3
            static let distance = 9
            static let arrival = 10
            static let departure = 11
        }

        /// `Caskody.txt`: line, run, sequence, code, **kind**, from, to, note.
        enum Exception {
            static let serviceNumber = 1
            static let kind = 4
            static let from = 5
            static let to = 6
        }

        enum Stop {
            static let name = 0
            static let municipality = 1
            static let part = 2
            static let localName = 3
        }
    }

    /// Parses the contents of one line's package.
    ///
    /// - Parameter files: file name to file contents, as taken out of the line's
    ///   zip. `Zasspoje.txt` and `Zastavky.txt` are required; `Spoje.txt`,
    ///   `Linky.txt` and `Dopravci.txt` fill in the rest when present.
    static func parse(files: [String: Data]) throws -> LineTimetable {
        guard let callsData = files["Zasspoje.txt"] else {
            throw Failure.missingFile("Zasspoje.txt")
        }
        let callRows = try rows(in: callsData, name: "Zasspoje.txt")
        guard let firstCall = callRows.first, Column.lineNumber < firstCall.count else {
            throw Failure.noLine
        }
        let lineNumber = firstCall[Column.lineNumber]

        // Stops: id -> "Obec,část". The archive writes the municipality with a
        // district suffix ("Brtnice [JI]") and then up to two more parts: the part
        // of the municipality and a local name such as "rozc.1.0". The last two
        // are not alternatives - 114 of 1055 stops in a sample of the archive have
        // both - and keeping only the first of them is what used to cut
        // "Zašovice,Nová Brtnice,rozc.1.0" down to its first two parts.
        var stopNames: [String: String] = [:]
        if let stopsData = files["Zastavky.txt"] {
            for row in try rows(in: stopsData, name: "Zastavky.txt") {
                guard Column.Stop.name < row.count, Column.Stop.municipality < row.count else { continue }
                let municipality = strippingDistrict(row[Column.Stop.municipality])
                let detail = [row[safe: Column.Stop.part], row[safe: Column.Stop.localName]]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: ",")
                stopNames[row[Column.Stop.name]] = detail.isEmpty
                    ? municipality
                    : "\(municipality),\(detail)"
            }
        }

        // Calls grouped into runs, in published order.
        var callsByRun: [String: [ScheduledCall]] = [:]
        for row in callRows {
            guard let serviceNumber = row[safe: Column.Call.serviceNumber],
                  let order = row[safe: Column.Call.order].flatMap(Int.init) else { continue }
            let stopID = row[safe: Column.Call.stopID] ?? ""
            let arrival = row[safe: Column.Call.arrival] ?? ""
            let departure = row[safe: Column.Call.departure] ?? ""
            callsByRun[serviceNumber, default: []].append(
                ScheduledCall(
                    order: order,
                    stopID: stopID,
                    stopName: stopNames[stopID] ?? "",
                    arrival: TimeOfDay(clock: arrival),
                    departure: TimeOfDay(clock: departure),
                    distanceKilometres: row[safe: Column.Call.distance].flatMap(Int.init),
                    // A call the run does not serve carries `<` or `|` in the time
                    // columns instead of a time, so it has none at all.
                    isServed: !(arrival.contains("<") || arrival.contains("|")
                        || departure.contains("<") || departure.contains("|")),
                )
            )
        }

        // The period the whole line is published for. `Linky.txt` states it once,
        // for every run: the archive calls it "platnost" and it is what the
        // timetable change in December ends.
        let line = try rows(in: files["Linky.txt"] ?? Data(), name: "Linky.txt").first
        var lineValidity: [ValidityPeriod] = []
        if let from = line?[safe: Column.Line.validityFrom].flatMap(ServiceDay.init(archiveText:)) {
            let to = line?[safe: Column.Line.validityTo].flatMap(ServiceDay.init(archiveText:))
            lineValidity = [ValidityPeriod(from: from, to: to)]
        }

        // Dated exceptions per run: "does not run 22.12.-2.1.", "runs only in the
        // school term", "runs in odd weeks". These are footnotes, not validity -
        // reading them as periods would turn "does not run in the holidays" into
        // "runs only in the holidays".
        var exceptionsByRun: [String: [RunCalendar.Exception]] = [:]
        if let exceptionData = files["Caskody.txt"] {
            for row in try rows(in: exceptionData, name: "Caskody.txt") {
                guard let serviceNumber = row[safe: Column.Exception.serviceNumber],
                      let from = row[safe: Column.Exception.from]
                        .flatMap(ServiceDay.init(archiveText:)) else { continue }
                let to = row[safe: Column.Exception.to].flatMap(ServiceDay.init(archiveText:))
                guard let kind = row[safe: Column.Exception.kind].flatMap(exceptionKind) else { continue }
                exceptionsByRun[serviceNumber, default: []].append(
                    RunCalendar.Exception(kind: kind, from: from, to: to)
                )
            }
        }

        // The header rules: `Spoje.txt` lists fixed codes per run, and
        // `Pevnykod.txt` says which symbol each code stands for. `X`, `+` and
        // `1`-`7` are the calendar ones; the rest are notes about accessibility,
        // bicycles and the like.
        var symbolByCode: [String: String] = [:]
        if let codeData = files["Pevnykod.txt"] {
            for row in try rows(in: codeData, name: "Pevnykod.txt") {
                guard let code = row[safe: Column.FixedCode.code],
                      let symbol = row[safe: Column.FixedCode.symbol] else { continue }
                symbolByCode[code] = symbol
            }
        }

        var rulesByRun: [String: Set<RunCalendar.Rule>] = [:]
        if let tripData = files["Spoje.txt"] {
            for row in try rows(in: tripData, name: "Spoje.txt") {
                guard let serviceNumber = row[safe: Column.Trip.serviceNumber] else { continue }
                for index in Column.Trip.firstAttribute...Column.Trip.lastAttribute {
                    guard let code = row[safe: index], !code.isEmpty,
                          let symbol = symbolByCode[code],
                          let rule = RunCalendar.rule(forSymbol: symbol) else { continue }
                    rulesByRun[serviceNumber, default: []].insert(rule)
                }
            }
        }

        let runs = callsByRun
            .map {
                ScheduledRun(
                    serviceNumber: $0.key,
                    calls: ScheduledRun.inTravelOrder($0.value),
                    validity: lineValidity,
                    calendar: RunCalendar(rules: rulesByRun[$0.key] ?? [],
                                          exceptions: exceptionsByRun[$0.key] ?? [])
                )
            }
            .sorted { $0.serviceNumber.compare($1.serviceNumber, options: .numeric) == .orderedAscending }

        let operators = try rows(in: files["Dopravci.txt"] ?? Data(), name: "Dopravci.txt")
        let operatorID = line?[safe: Column.Line.operatorID]
        let operatorName = operators
            .first { $0[safe: Column.lineNumber] == operatorID }
            .flatMap { $0[safe: Column.Operator.name] }

        return LineTimetable(
            lineNumber: lineNumber,
            displayNumber: LineCode(raw: lineNumber).number,
            routeName: line?[safe: Column.Line.routeName] ?? "",
            operatorName: operatorName.flatMap { $0.isEmpty ? nil : $0 },
            runs: runs,
            validity: lineValidity
        )
    }

    /// The `Typ časového kódu` column, as the archive writes it.
    private static func exceptionKind(_ text: String) -> RunCalendar.Exception.Kind? {
        switch text.trimmingCharacters(in: .whitespaces) {
        case "1": return .service
        case "2": return .serviceAlso
        case "3": return .serviceOnly
        case "4": return .noService
        case "5": return .oddWeeks
        case "6": return .evenWeeks
        case "7": return .oddWeeksFromTo
        case "8": return .evenWeeksFromTo
        default: return nil
        }
    }

    /// Rows of a JDF file, each a list of unquoted fields.
    static func rows(in data: Data, name: String) throws -> [[String]] {
        guard !data.isEmpty else { return [] }
        guard let text = String(data: data, encoding: .windowsCP1250)
            ?? String(data: data, encoding: .utf8) else {
            throw Failure.notText(name)
        }
        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                var row = line.trimmingCharacters(in: .whitespaces)
                guard !row.isEmpty else { return nil }
                if row.hasSuffix(";") { row.removeLast() }
                if row.hasPrefix("\"") { row.removeFirst() }
                if row.hasSuffix("\"") { row.removeLast() }
                return row.components(separatedBy: "\",\"")
            }
    }

    /// "Brtnice [JI]" is Brtnice in the Jihlava district; the suffix is only
    /// there to disambiguate, so it is dropped for display.
    private static func strippingDistrict(_ name: String) -> String {
        lineStrippingDistrict(name)
    }

    private static func lineStrippingDistrict(_ name: String) -> String {
        guard let open = name.firstIndex(of: "["), let close = name[open...].firstIndex(of: "]") else {
            return name.trimmingCharacters(in: .whitespaces)
        }
        var cleaned = name
        cleaned.removeSubrange(open...close)
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
