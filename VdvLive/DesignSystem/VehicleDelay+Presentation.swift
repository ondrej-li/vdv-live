import SwiftUI

extension VehicleDelay {
    /// Colour flagging how far off schedule a vehicle is.
    var tint: Color {
        switch self {
        case .unknown:
            return .secondary
        case .minutes(let minutes):
            if isBadlyLate { return .red }
            if minutes > 0 { return .orange }
            return .green
        }
    }
}
