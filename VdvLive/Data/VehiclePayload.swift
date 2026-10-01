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
