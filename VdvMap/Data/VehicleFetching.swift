import Foundation

/// Source of vehicle positions.
///
/// A protocol rather than a concrete type so that tests and previews can answer
/// without touching the network.
protocol VehicleFetching: Sendable {
    func fetchVehicles() async throws -> VehiclePayload
}
