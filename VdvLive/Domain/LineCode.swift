import Foundation

/// A line as passengers know it, separated from the operator prefix the feed
/// carries.
///
/// The feed's `text` field is the operator's internal code, which for buses is
/// usually six digits: three for the operator plus three for the line. `764337`
/// is therefore line `337` run by operator `764`. Everything else - train
/// numbers, the short codes used on some regional lines - is already the line
/// itself.
struct LineCode: Hashable, Sendable {
    /// Value as the feed sends it.
    let raw: String
    /// Operator prefix, `nil` when the code does not carry one.
    let operatorCode: String?
    /// Line number as it is shown to passengers.
    let number: String

    init(raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.raw = trimmed

        guard trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else {
            self.operatorCode = nil
            self.number = trimmed
            return
        }

        let prefix = String(trimmed.prefix(3))
        let suffix = String(trimmed.suffix(3))
        self.operatorCode = prefix
        self.number = Self.strippingLeadingZeros(suffix)
    }

    /// Whether the code identifies the line, whether or not the operator
    /// prefix was written out.
    func matches(_ other: LineCode) -> Bool {
        number == other.number
    }

    /// Text shown on a marker, chip or list row.
    var displayText: String { number }

    /// Everything the feed said, for the detail card.
    var fullText: String { raw }

    private static func strippingLeadingZeros(_ value: String) -> String {
        // "036" and "36" are the same line; "000" only ever appears as "0".
        let stripped = String(value.drop { $0 == "0" })
        return stripped.isEmpty ? "0" : stripped
    }
}
