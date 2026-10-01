import Foundation
@testable import VdvLive

/// Payload store that keeps what it is given in memory, so that a test neither
/// reads nor writes the caches directory of the app it runs inside - which would
/// otherwise leak the last payload from one test into the next launch.
///
/// `@unchecked Sendable` because the mutable state is only touched from the main
/// actor in tests.
final class InMemoryVehiclePayloadStore: VehiclePayloadStoring, @unchecked Sendable {
    /// What `load()` hands back, which is also the last thing saved.
    private(set) var stored: StoredVehiclePayload?
    /// Everything written through `save`, oldest first, so a test can count them.
    private(set) var saves: [StoredVehiclePayload] = []

    init(stored: StoredVehiclePayload? = nil) {
        self.stored = stored
    }

    func load() -> StoredVehiclePayload? { stored }

    func save(_ payload: VehiclePayload, fetchedAt: Date) {
        let entry = StoredVehiclePayload(payload: payload, fetchedAt: fetchedAt)
        saves.append(entry)
        stored = entry
    }
}
