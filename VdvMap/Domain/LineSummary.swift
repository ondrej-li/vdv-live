import Foundation

/// A line with the vehicles that are reporting on it right now.
///
/// The favourites screen needs this for lines that are pinned but idle: they
/// get a summary with a count of zero rather than disappearing from the list.
struct LineSummary: Hashable, Identifiable, Sendable {
    /// Line number as passengers know it, operator prefix removed.
    let line: String
    /// Operator running the line, when the feed's code carries one.
    let operatorCode: String?
    let vehicleCount: Int
    let traction: Traction

    var id: String { line }

    var isRunning: Bool { vehicleCount > 0 }

    var vehicleCountText: String {
        switch vehicleCount {
        case 0: return String(localized: "no vehicles right now")
        default: return String(format: String(localized: "%lld vehicles"), vehicleCount)
        }
    }

    /// Traction, plus the operator when the feed identifies one.
    var descriptionText: String {
        guard isRunning else { return String(localized: "not running") }
        guard let operatorCode else { return traction.displayName }
        return String(
            format: String(localized: "%@ · operator %@"),
            traction.displayName,
            operatorCode
        )
    }

    /// Summary for a line that is not reporting anything, e.g. a pinned line
    /// outside its hours of operation.
    static func idle(_ line: String, operatorCode: String? = nil) -> LineSummary {
        LineSummary(line: line, operatorCode: operatorCode, vehicleCount: 0, traction: .unknown)
    }
}
