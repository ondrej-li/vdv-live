import Foundation

/// What the app keeps for the next launch: the last payload it managed to fetch,
/// and when it fetched it.
///
/// The time matters as much as the vehicles. A cold start with no network can then
/// say *how old* what it is showing is, which is the difference between "the last
/// known state" and "the map".
struct StoredVehiclePayload: Codable, Equatable, Sendable {
    var payload: VehiclePayload
    var fetchedAt: Date
}

/// Where the last payload is kept between launches.
protocol VehiclePayloadStoring: Sendable {
    /// The last payload, or `nil` when there is none to be had.
    func load() -> StoredVehiclePayload?
    func save(_ payload: VehiclePayload, fetchedAt: Date)
}

/// File-backed store, in the caches directory.
///
/// The caches directory is the right home for this: it is the last known state and
/// nothing more, so the system throwing it away costs the app nothing worse than
/// the empty map it would have shown without it.
struct VehiclePayloadFiles: VehiclePayloadStoring {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("payload", isDirectory: true)
        }
    }

    private var fileURL: URL { directory.appendingPathComponent("last-payload.json") }

    func load() -> StoredVehiclePayload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        // A file this build cannot read - written by another version, or cut short
        // by the system - is simply not there as far as the app is concerned.
        return try? JSONDecoder().decode(StoredVehiclePayload.self, from: data)
    }

    func save(_ payload: VehiclePayload, fetchedAt: Date) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stored = StoredVehiclePayload(payload: payload, fetchedAt: fetchedAt)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
