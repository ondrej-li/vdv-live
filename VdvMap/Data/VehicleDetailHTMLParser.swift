import Foundation

/// Parses the small HTML fragments the map's own AJAX endpoints return.
///
/// Neither `/Ajax/OpenInfoWindow` nor `/Ajax/GetTimetable` speaks JSON, so the
/// label/value table and the stop rows are picked out of the markup directly.
/// The shape is stable - the site renders it with a plain Bulma table - and the
/// parser is written to return `nil` fields rather than throw when a row it
/// expects is missing.
enum VehicleDetailHTMLParser {
    /// Fields of the vehicle popup.
    struct InfoWindow: Equatable, Sendable {
        let line: String?
        let serviceNumber: String?
        let stopName: String?
        let reportedDelayMinutes: Int?
        let isBarrierFree: Bool?
    }

    static func parseInfoWindow(_ html: String) throws -> InfoWindow {
        var line: String?
        var serviceNumber: String?
        var stopName: String?
        var reportedDelayMinutes: Int?
        var isBarrierFree: Bool?

        for (label, valueMarkup) in labelledRows(in: html) {
            switch field(for: label) {
            case .line:
                line = cleanText(valueMarkup)
            case .serviceNumber:
                serviceNumber = cleanText(valueMarkup)
            case .stopName:
                stopName = cleanText(valueMarkup)
            case .delay:
                reportedDelayMinutes = leadingInteger(in: cleanText(valueMarkup))
            case .barrierFree:
                // The site renders this row as a disabled checkbox that is only
                // ticked for accessible vehicles.
                isBarrierFree = valueMarkup.contains("checked")
            case nil:
                break
            }
        }

        return InfoWindow(
            line: line,
            serviceNumber: serviceNumber,
            stopName: stopName,
            reportedDelayMinutes: reportedDelayMinutes,
            isBarrierFree: isBarrierFree
        )
    }

    /// Which run the timetable page describes, from its `Linkospoj: 420 / 11`
    /// heading. `nil` when the page says `-- / --`, which is how it reports a
    /// timetable it could not load.
    struct RunLabel: Equatable, Sendable {
        let line: String
        let serviceNumber: String
    }

    static func parseRunLabel(_ html: String) throws -> RunLabel? {
        guard
            let markup = firstMatch(in: html, pattern: "Linkospoj:.*?<span[^>]*>(.*?)</span>"),
            let value = cleanText(markup)
        else {
            return nil
        }

        let parts = value
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, parts[0] != "--", parts[1] != "--" else { return nil }
        return RunLabel(line: parts[0], serviceNumber: parts[1])
    }

    /// Stops of the run, in the order the timetable lists them.
    static func parseRunStops(_ html: String) throws -> [RunStop] {
        let body = firstMatch(in: html, pattern: "<tbody>(.*?)</tbody>") ?? html
        var stops: [RunStop] = []

        for row in allMatches(in: body, pattern: "<tr>(.*?)</tr>") {
            let cells = allMatches(in: row, pattern: "<td[^>]*>(.*?)</td>")
            guard let nameMarkup = cells.first else { continue }
            let name = cleanText(nameMarkup) ?? ""
            guard !name.isEmpty else { continue }

            stops.append(
                RunStop(
                    name: name,
                    arrival: cells.indices.contains(1) ? timeText(cells[1]) : nil,
                    departure: cells.indices.contains(2) ? timeText(cells[2]) : nil
                )
            )
        }

        return stops
    }

    // MARK: - Markup helpers

    private enum Field {
        case line
        case serviceNumber
        case stopName
        case delay
        case barrierFree
    }

    /// Which field a table row carries.
    ///
    /// The feed is not consistent about its own labels - the accessibility row
    /// is spelled `Bezbarierový`, without the háček - so labels are compared
    /// with diacritics folded away rather than character by character.
    private static func field(for label: String) -> Field? {
        let key = fold(label)
        if key == fold("Linka") { return .line }
        if key == fold("Spoj") { return .serviceNumber }
        if key == fold("Zastávka") { return .stopName }
        if key == fold("Zpoždění") { return .delay }
        if key == fold("Bezbariérový") || key == fold("Bezbarierový") { return .barrierFree }
        return nil
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every `<th>label</th><td>value</td>` pair of a table.
    private static func labelledRows(in html: String) -> [(String, String)] {
        let pattern = "<th[^>]*>(.*?)</th>\\s*<td[^>]*>(.*?)</td>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let input = html as NSString
        return regex
            .matches(in: html, range: NSRange(location: 0, length: input.length))
            .compactMap { match in
                guard
                    match.numberOfRanges > 2,
                    let label = cleanText(input.substring(with: match.range(at: 1)))
                else {
                    return nil
                }
                return (label, input.substring(with: match.range(at: 2)))
            }
    }

    /// Text of a cell, or `nil` for the placeholders the timetable uses when a
    /// stop has no time.
    private static func timeText(_ markup: String) -> String? {
        guard let text = cleanText(markup), text != "--", text != "-" else { return nil }
        return text
    }

    /// Strips tags, decodes entities, collapses whitespace and drops a trailing
    /// colon, so that a label compares as `Zastávka`.
    private static func cleanText(_ markup: String) -> String? {
        var text = markup.replacingOccurrences(
            of: "<[^>]*>",
            with: " ",
            options: [.regularExpression]
        )
        text = HTMLEntities.decode(text)
            .replacingOccurrences(of: "\\s+", with: " ", options: [.regularExpression])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(":") {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return text.isEmpty ? nil : text
    }

    /// `0 min.` and `-3 min.` both give a number.
    private static func leadingInteger(in text: String?) -> Int? {
        guard let text else { return nil }
        let prefix = text.prefix { $0.isNumber || $0 == "-" || $0 == "+" }
        return Int(prefix)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        allMatches(in: text, pattern: pattern).first
    }

    private static func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let input = text as NSString
        return regex
            .matches(in: text, range: NSRange(location: 0, length: input.length))
            .map { match in
                match.numberOfRanges > 1
                    ? input.substring(with: match.range(at: 1))
                    : input.substring(with: match.range)
            }
    }
}
