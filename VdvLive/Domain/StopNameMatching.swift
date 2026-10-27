import Foundation

/// How well a stop name answers what was typed, for a search field that has to cope
/// with how people actually type: `nova brtnice` for `Nová Brtnice`, and a slipped
/// finger like `nova betnice` for the same stop.
///
/// Both sides are folded the way the shipped stop table is keyed - case, diacritics,
/// spaces and punctuation dropped - so a search never depends on accents. Matching is
/// ranked rather than merely filtered: an exact name beats a prefix, a prefix beats a
/// name that only contains the text, and all of those beat a near miss.
enum StopNameMatching {
    /// How directly a name answers a query. Lower is a better answer.
    enum Quality: Int, Comparable, Sendable {
        case exact = 0
        case prefix = 1
        case contains = 2
        case words = 3
        case fuzzy = 4

        static func < (lhs: Quality, rhs: Quality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The key a name is compared by: letters and digits only, case and accents gone.
    static func key(for name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
        return folded.unicodeScalars.reduce(into: "") { key, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                key.unicodeScalars.append(scalar)
            }
        }
    }

    /// How well `name` answers `text`, or `nil` when it does not answer it at all.
    static func quality(of name: String, matching text: String) -> Quality? {
        let query = key(for: text)
        guard !query.isEmpty else { return nil }
        return quality(ofKey: key(for: name), matchingKey: query, name: name, queryText: text)
    }

    /// Whether a name is worth showing at all. The same rule as ``quality(of:matching:)``
    /// without the ranking, for callers that do not sort.
    static func matches(_ name: String, query text: String) -> Bool {
        quality(of: name, matching: text) != nil
    }

    private static func quality(
        ofKey nameKey: String,
        matchingKey query: String,
        name: String,
        queryText: String
    ) -> Quality? {
        if nameKey == query { return .exact }
        if nameKey.hasPrefix(query) { return .prefix }
        if nameKey.contains(query) { return .contains }
        if matchesWordPrefixes(of: name, query: queryText) { return .words }
        if editDistance(nameKey, query) <= tolerance(for: query) { return .fuzzy }
        return nil
    }

    /// "nova brt" finds "Nová Brtnice,aut.nádr.": every word that was typed is the
    /// beginning of a word in the name, though not necessarily of the name itself.
    private static func matchesWordPrefixes(of name: String, query: String) -> Bool {
        let nameWords = words(of: name)
        let queryWords = words(of: query)
        guard !nameWords.isEmpty, !queryWords.isEmpty else { return false }
        let needles = queryWords
        return needles.allSatisfy { needle in
            nameWords.contains { $0.hasPrefix(needle) }
        }
    }

    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { key(for: String($0)) }
            .filter { !$0.isEmpty }
    }

    /// How far a name may drift from the typed text and still be offered.
    ///
    /// One edit for a short query, more as it grows: `nova betnice` (one wrong letter)
    /// still finds its stop, while a two-letter query does not match half the region.
    static func tolerance(for query: String) -> Int {
        min(3, max(1, query.count / 4))
    }

    /// Levenshtein distance, with the cheaper "give up past `limit`" exit: a name
    /// longer or shorter than the query by more than the tolerance cannot match, and
    /// the rest are abandoned as soon as the row minimum exceeds it.
    static func editDistance(_ lhs: String, _ rhs: String, limit: Int = .max) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if abs(left.count - right.count) > limit { return limit + 1 }
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for i in 1...left.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...right.count {
                let substitution = previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
                rowMinimum = min(rowMinimum, current[j])
            }
            if rowMinimum > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}
