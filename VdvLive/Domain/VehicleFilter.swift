import Foundation

/// What the map is currently showing.
enum VehicleFilter: Hashable, Sendable {
    /// Every vehicle in the feed.
    case all
    /// Only vehicles whose line is pinned.
    case favourites
    /// Only vehicles of one traction.
    case traction(Traction)
}
