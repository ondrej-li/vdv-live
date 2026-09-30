import SwiftUI

extension VehicleFilter {
    /// Text of the filter chip.
    var displayName: String {
        switch self {
        case .all: return String(localized: "All")
        case .favourites: return String(localized: "Pinned")
        case .traction(let traction): return traction.displayName
        }
    }

    /// Colour of the filter chip when it is selected.
    ///
    /// Pinned uses a colour no traction uses, so that the chip cannot be
    /// confused with a traction filter.
    var tint: Color {
        switch self {
        case .all: return .accentColor
        case .favourites: return .orange
        case .traction(let traction): return traction.tint
        }
    }

    /// Colour of the star that marks a pinned line.
    static let favouriteTint = Color.yellow
}
