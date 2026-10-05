import SwiftUI

/// The colour of a vehicle on the watch, which is the only thing its dot says.
///
/// Kept next to the watch rather than beside the phone's delay colours: the phone
/// turns red five minutes earlier and its markers carry text to explain the extra
/// orange - the watch has neither.
extension DelayBand {
    var tint: Color {
        switch self {
        case .onTime:
            return .green
        case .late:
            return .orange
        case .veryLate:
            return .red
        case .unknown:
            return .gray
        }
    }

    /// What to write on top of ``tint``.
    ///
    /// Black on the pale bands and white on the dark ones, because a line number
    /// nobody can read is worse than no line number at all.
    var onTint: Color {
        switch self {
        case .onTime, .late:
            return .black
        case .veryLate, .unknown:
            return .white
        }
    }
}
