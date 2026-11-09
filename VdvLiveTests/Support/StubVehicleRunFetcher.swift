import Foundation
@testable import VdvLive

/// Run fetcher that answers from a script instead of the network.
///
/// `@unchecked Sendable` because the mutable state is only touched from the
/// main actor in tests.
final class StubVehicleRunFetcher: VehicleRunFetching, @unchecked Sendable {
    /// Answers by vehicle id; a vehicle without one is read as a failure.
    var runs: [Int: VehicleRun] = [:]
    /// Answer used for every vehicle, which is the usual case.
    var run: VehicleRun?
    var error: Error?
    private(set) var requestedVehicleIDs: [Int] = []

    init(run: VehicleRun? = nil, runs: [Int: VehicleRun] = [:], error: Error? = nil) {
        self.run = run
        self.runs = runs
        self.error = error
    }

    func fetchRun(for vehicle: Vehicle) async throws -> VehicleRun {
        requestedVehicleIDs.append(vehicle.id)
        if let error {
            throw error
        }
        guard let run = runs[vehicle.id] ?? run else {
            throw VehicleAPIError.malformedPayload("No run in the script.")
        }
        return run
    }
}
