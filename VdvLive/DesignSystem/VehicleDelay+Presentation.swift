import SwiftUI

extension VehicleDelay {
    /// Compact label for the detail card, e.g. `+5 min`, `-3 min`, `on time`.
    var displayText: String {
        switch self {
        case .unknown:
            return String(localized: "no data")
        case .minutes(0):
            return String(localized: "on time")
        case .minutes(let minutes) where minutes > 0:
            return String(format: String(localized: "+%lld min"), minutes)
        case .minutes(let minutes):
            return String(format: String(localized: "%lld min"), minutes)
        }
    }

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
