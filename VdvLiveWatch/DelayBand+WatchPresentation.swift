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
}
