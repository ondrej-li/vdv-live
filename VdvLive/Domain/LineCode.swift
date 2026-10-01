import Foundation

/// A line as passengers know it, separated from the prefix the feed carries.
///
/// The feed's `text` field is the number the line is registered under, which for
/// buses is usually six digits: three for the licence area the line is filed in,
/// three for the number carried on the bus. `764337` is therefore line `337` in
/// licence area `764`. Everything else - train numbers, the short codes used on
/// some regional lines - is already the line itself.
struct LineCode: Hashable, Sendable {
    /// Value as the feed sends it.
    let raw: String
    /// Licence area prefix, `nil` when the code does not carry one.
    let licenceAreaCode: String?
    /// Line number as it is shown to passengers.
    let number: String

    init(raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.raw = trimmed

        guard trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else {
            self.licenceAreaCode = nil
            self.number = trimmed
            return
        }

        let prefix = String(trimmed.prefix(3))
        let suffix = String(trimmed.suffix(3))
        self.licenceAreaCode = prefix
        self.number = Self.strippingLeadingZeros(suffix)
    }

    /// Whether the code identifies the line, whether or not the licence area
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
