import Foundation

/// Decodes the character references the map's HTML fragments use.
///
/// The server escapes every non-ASCII character numerically and in
/// hexadecimal: `Tel&#x10D;,Hradeck&#xE1; &#x161;kola` is
/// `Telč,Hradecká škola`.
enum HTMLEntities {
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return replacingNumeric(in: replacingNamed(in: text))
    }

    private static let named: [(entity: String, replacement: String)] = [
        ("&nbsp;", " "),
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&apos;", "'"),
        ("&#39;", "'")
    ]

    private static func replacingNamed(in text: String) -> String {
        var result = text
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    /// Pattern is `&#x10D;` or `&#269;`: an optional `x` selects hexadecimal.
    private static let numericPattern = try? NSRegularExpression(
        pattern: "&#(x?)([0-9A-Fa-f]+);",
        options: []
    )

    private static func replacingNumeric(in text: String) -> String {
        guard let numericPattern else { return text }
        let input = text as NSString
        let matches = numericPattern.matches(
            in: text,
            range: NSRange(location: 0, length: input.length)
        )
        guard !matches.isEmpty else { return text }

        var result = ""
        var location = 0
        for match in matches {
            result += input.substring(
                with: NSRange(location: location, length: match.range.location - location)
            )
            let isHexadecimal = input.substring(with: match.range(at: 1)) == "x"
            let digits = input.substring(with: match.range(at: 2))
            if let value = UInt32(digits, radix: isHexadecimal ? 16 : 10),
               let scalar = Unicode.Scalar(value) {
                result.unicodeScalars.append(scalar)
            } else {
                result += input.substring(with: match.range)
            }
            location = match.range.location + match.range.length
        }
        result += input.substring(from: location)
        return result
    }
}
