import SwiftUI

extension Traction {
    /// Colour of a marker or badge for this traction.
    var tint: Color {
        switch self {
        case .bus: return .blue
        case .trolleybus: return .teal
        case .tram: return .purple
        case .train: return .indigo
        case .ferry: return .cyan
        case .unknown: return .gray
        }
    }

    /// SF Symbol shown next to a vehicle in the detail card.
    ///
    /// All names used here exist since iOS 15 or earlier, well below the
    /// deployment target.
    var symbolName: String {
        switch self {
        case .bus, .trolleybus: return "bus.fill"
        case .tram: return "tram.fill"
        case .train: return "train.side.front.car"
        case .ferry: return "ferry.fill"
        case .unknown: return "questionmark"
        }
    }

    var displayName: String {
        switch self {
        case .bus: return String(localized: "Bus")
        case .trolleybus: return String(localized: "Trolleybus")
        case .tram: return String(localized: "Tram")
        case .train: return String(localized: "Train")
        case .ferry: return String(localized: "Ferry")
        case .unknown: return String(localized: "Unknown")
        }
    }
}
