import Foundation
@testable import VdvLive

/// Detail fetcher that answers from a script instead of the network.
///
/// `@unchecked Sendable` because the mutable state is only touched from the
/// main actor in tests.
final class StubVehicleDetailFetcher: VehicleDetailFetching, @unchecked Sendable {
    var detail: VehicleDetail?
    var error: Error?
    /// Delay before answering, to exercise the loading state and races.
    var delay: Duration = .zero
    private(set) var requestedVehicleIDs: [Int] = []

    init(detail: VehicleDetail? = nil, error: Error? = nil, delay: Duration = .zero) {
        self.detail = detail
        self.error = error
        self.delay = delay
    }

    func fetchDetail(for vehicle: Vehicle) async throws -> VehicleDetail {
        requestedVehicleIDs.append(vehicle.id)
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        if let error {
            throw error
        }
        return detail ?? VehicleDetail(
            lineCode: vehicle.lineCode,
            serviceNumber: nil,
            isBarrierFree: nil,
            stopName: "Stop \(vehicle.id)",
            reportedDelayMinutes: nil,
            runStops: []
        )
    }
}
