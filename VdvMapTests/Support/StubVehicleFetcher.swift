import Foundation
@testable import VdvMap

/// Fetcher that answers from a script instead of the network.
///
/// `@unchecked Sendable` because the mutable state is only touched from the
/// main actor in tests.
final class StubVehicleFetcher: VehicleFetching, @unchecked Sendable {
    /// Payloads handed out in order; the last one repeats.
    var payloads: [VehiclePayload] = []
    /// When set, thrown instead of returning a payload.
    var error: Error?
    private(set) var callCount = 0

    init(payloads: [VehiclePayload] = []) {
        self.payloads = payloads
    }

    init(vehicles: [Vehicle], error: Error? = nil) {
        self.payloads = [
            VehiclePayload(vehicles: vehicles, skippedRecordCount: 0, unlocatableRecordCount: 0)
        ]
        self.error = error
    }

    func fetchVehicles() async throws -> VehiclePayload {
        callCount += 1
        if let error {
            throw error
        }
        guard !payloads.isEmpty else { return .empty }
        return payloads[min(callCount - 1, payloads.count - 1)]
    }
}
