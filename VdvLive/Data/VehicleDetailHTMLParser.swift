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
            let text = cleanText(valueMarkup)
            switch field(for: label) {
            case .lineAndService:
                // `Linka / spoj` → `766420 / 109`, which is how the popup reads
                // since November 2026. Splitting it is the difference between a
                // card with the vehicle's stop list and a card with nothing.
                let parts = (text ?? "")
                    .split(separator: "/", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { break }
                line = parts[0]
                serviceNumber = parts[1]
            case .line:
                line = text
            case .serviceNumber:
                serviceNumber = text
            case .stopName:
                stopName = text
            case .delay:
                // The feed writes Int32.min when it has no delay to report.
                // Carrying that on as minutes shows "-2147483648 min" in the
                // card and moves every stop of the run to midnight in the list.
                let minutes = leadingInteger(in: text)
                reportedDelayMinutes = minutes == VehicleDelay.unknownSentinel ? nil : minutes
            case .barrierFree:
                // Once a checkbox that is only ticked for accessible vehicles, now
                // the word `Ano` or `Ne`: both say the same thing.
                isBarrierFree = valueMarkup.contains("checked")
                    || (text.map { fold($0) == fold("Ano") } ?? false)
            case nil:
                break
            }
        }

        // The delay is a badge above the facts now, and `Včas` is zero rather than
        // "no information".
        if reportedDelayMinutes == nil,
           let badge = firstMatch(in: html, pattern: "<span class=\"delay-value\">(.*?)</span>"),
           let text = cleanText(badge) {
            reportedDelayMinutes = fold(text) == fold("Včas") ? 0 : leadingInteger(in: text)
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
        // `Linka 766420, spoj 109`, the heading the page carries now.
        if let caption = firstMatch(in: html, pattern: "<p class=\"ride-caption\">(.*?)</p>"),
           let text = cleanText(caption) {
            let digits = numbers(in: text)
            if digits.count >= 2 {
                return RunLabel(line: digits[0], serviceNumber: digits[1])
            }
        }

        // `Linkospoj: 420 / 11`, the heading it carried before.
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

    /// The runs of digits in a piece of text, in order: `Linka 766420, spoj 109`
    /// gives `766420` and `109` without depending on the words around them.
    private static func numbers(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "[0-9]+") else { return [] }
        let input = text as NSString
        return regex
            .matches(in: text, range: NSRange(location: 0, length: input.length))
            .map { input.substring(with: $0.range) }
    }

    /// Stops of the run, in the order the timetable lists them.
    static func parseRunStops(_ html: String) throws -> [RunStop] {
        let body = firstMatch(in: html, pattern: "<tbody>(.*?)</tbody>") ?? html
        var stops: [RunStop] = []

        for row in allMatches(in: body, pattern: "<tr[^>]*>(.*?)</tr>") {
            let cells = allMatches(in: row, pattern: "<td[^>]*>(.*?)</td>")
            guard let nameMarkup = cells.first else { continue }

            // The page prints one time column now ("Plán"), and an arrival inside the
            // stop's own cell where it is worth showing. It used to print an arrival
            // column and a departure column; both shapes are read, because a card
            // with no stops is worse than one reading an older page.
            let arrival = firstMatch(in: nameMarkup, pattern: "<span class=\"stop-arrival\">(.*?)</span>")
                .flatMap { cleanText($0) }
                .flatMap { firstMatch(in: $0, pattern: "[0-9]{1,2}:[0-9]{2}") }
            let name = cleanText(
                nameMarkup.replacingOccurrences(of: "<span class=\"stop-arrival\">.*?</span>",
                                                with: "",
                                                options: [.regularExpression])
            ) ?? ""
            guard !name.isEmpty else { continue }

            let planned = cells.indices.contains(1) ? timeText(cells[1]) : nil
            let departureTime = cells.indices.contains(2) ? timeText(cells[2]) : nil

            stops.append(
                RunStop(
                    name: name,
                    // Two cells: the stop and when the run leaves it.
                    // Three cells: an arrival column and a departure column.
                    arrival: departureTime == nil ? arrival : (arrival ?? planned),
                    departure: departureTime ?? planned
                )
            )
        }

        return stops
    }

    // MARK: - Markup helpers

    private enum Field {
        case line
        case serviceNumber
        /// `Linka / spoj`, naming both in one row.
        case lineAndService
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
        if key == fold("Linka / spoj") { return .lineAndService }
        if key == fold("Zastávka") || key == fold("Poslední zastávka") { return .stopName }
        if key == fold("Zpoždění") { return .delay }
        if key == fold("Bezbariérový") || key == fold("Bezbarierový")
            || key == fold("Bezbariérové vozidlo") { return .barrierFree }
        return nil
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every label/value pair the popup is made of, in either shape it has had.
    ///
    /// It was a `<th>label</th><td>value</td>` table until November 2026; since then
    /// it is a `<dt>label</dt><dd>value</dd>` description list. Reading both costs
    /// one pattern, and is why a redesign of a page the app only reads is not a
    /// redesign of the app.
    private static func labelledRows(in html: String) -> [(String, String)] {
        pairs(in: html, label: "th", value: "td") + pairs(in: html, label: "dt", value: "dd")
    }

    private static func pairs(in html: String, label: String, value: String) -> [(String, String)] {
        let pattern = "<\(label)[^>]*>(.*?)</\(label)>\\s*<\(value)[^>]*>(.*?)</\(value)>"
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
