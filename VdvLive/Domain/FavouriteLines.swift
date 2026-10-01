import Foundation

/// The set of lines the user pinned.
///
/// A line is identified by the feed's `text` field, which is the line number as
/// passengers know it (`420`, `841334`, `5907`). Lines are normalised to
/// uppercase without surrounding whitespace so that a manually typed `420`
/// matches whatever the feed reports.
struct FavouriteLines: Hashable, Sendable {
    private(set) var lines: Set<String>

    init<S: Sequence<String>>(_ lines: S = []) {
        self.lines = Set(lines.map(Self.normalize).filter { !$0.isEmpty })
    }

    var isEmpty: Bool { lines.isEmpty }
    var count: Int { lines.count }

    func contains(_ line: String) -> Bool {
        lines.contains(Self.normalize(line))
    }

    /// Pins the line when it was not pinned, unpins it otherwise.
    /// Returns the state after the change.
    @discardableResult
    mutating func toggle(_ line: String) -> Bool {
        let normalized = Self.normalize(line)
        guard !normalized.isEmpty else { return false }
        if lines.contains(normalized) {
            lines.remove(normalized)
            return false
        }
        lines.insert(normalized)
        return true
    }

    mutating func pin(_ line: String) {
        let normalized = Self.normalize(line)
        guard !normalized.isEmpty else { return }
        lines.insert(normalized)
    }

    mutating func unpin(_ line: String) {
        lines.remove(Self.normalize(line))
    }

    /// Lines ordered the way a reader expects: numeric codes ascending, then
    /// anything else alphabetically.
    var orderedForDisplay: [String] {
        lines.sorted(by: Self.isOrderedBefore)
    }

    /// Lines are stored the way a passenger writes them down, so a feed code
    /// carrying a licence area prefix (`764337`) is filed as line `337`.
    static func normalize(_ line: String) -> String {
        LineCode(raw: line).number.uppercased()
    }

    /// Ordering shared by the pinned list and by the list of running lines.
    static func isOrderedBefore(_ lhs: String, _ rhs: String) -> Bool {
        switch (Int(lhs), Int(rhs)) {
        case let (left?, right?):
            return left == right ? lhs < rhs : left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs < rhs
        }
    }
}
