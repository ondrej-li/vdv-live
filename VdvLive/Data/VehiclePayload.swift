import Foundation

/// Outcome of one successful fetch: the vehicles worth putting on the map, plus
/// the number of records that had to be dropped on the way.
struct VehiclePayload: Codable, Equatable, Sendable {
    let vehicles: [Vehicle]
    /// Records the decoder could not read at all.
    let skippedRecordCount: Int
    /// Records without a usable position, i.e. reporting `lat: 0, lng: 0`.
    let unlocatableRecordCount: Int

    static let empty = VehiclePayload(vehicles: [], skippedRecordCount: 0, unlocatableRecordCount: 0)
}

extension VehiclePayload {
    /// The vehicles that belong on a map of these lines.
    ///
    /// Two rules, both of them about what a map can honestly draw: the feed's own
    /// idea of a usable position, and the lines that are pinned *now* rather than
    /// the ones pinned when the payload was fetched. The second is what lets a
    /// payload kept from an earlier launch answer a line pinned in the meantime,
    /// which is exactly the case a watch with no network is in.
    ///
    /// It lives here rather than in the watch's map so that the iOS test target,
    /// which cannot see the watch's sources, can cover it.
    func vehicles(onPinnedLines lines: FavouriteLines) -> [Vehicle] {
        vehicles.filter { $0.isLocatable && lines.contains($0.line) }
    }
}
