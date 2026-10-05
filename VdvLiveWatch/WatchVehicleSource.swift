import Foundation

/// Where the watch app gets its vehicles from.
enum WatchVehicleSource {
    /// The live regional feed, unless the app was launched with `-watchDelayBands`,
    /// which swaps in one sample per band so the colours can be looked at on a watch
    /// without waiting for a late bus to drive past.
    static var fetcher: VehicleFetching {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-watchDelayBands") {
            return DelayBandSampleFetcher()
        }
        if ProcessInfo.processInfo.arguments.contains("-watchOffline") {
            return OfflineFetcher()
        }
        #endif
        return VehicleAPIClient()
    }
}

#if DEBUG
/// A feed that never answers, so the map's behaviour with no network - which for a
/// watch is an ordinary Tuesday - can be looked at without unplugging anything.
private struct OfflineFetcher: VehicleFetching {
    func fetchVehicles() async throws -> VehiclePayload {
        throw VehicleAPIError.transport(String(localized: "There is no internet connection."))
    }
}
#endif

#if DEBUG
/// Four vehicles in a loose square near Jihlava, one in each delay band.
///
/// They wear the lines pinned on the phone, because the map would filter anything
/// else out, and they are spread far enough apart to stay separate dots at the zoom
/// the map opens at.
private struct DelayBandSampleFetcher: VehicleFetching {
    func fetchVehicles() async throws -> VehiclePayload {
        let centre = RegionOfInterest.vysocina.region.center
        let lines = UserDefaultsFavouriteLinesStore().load().orderedForDisplay
        let samples: [(minutes: Int, latitudeOffset: Double, longitudeOffset: Double)] = [
            (2, 0, 0),                                  // green: on time
            (7, 0, 0.12),                               // amber: late
            (14, -0.10, 0),                             // red: very late
            (VehicleDelay.unknownSentinel, -0.10, 0.12) // grey: the feed said nothing
        ]

        let vehicles = samples.enumerated().map { index, sample in
            Vehicle(
                id: -(index + 1),
                line: lines.isEmpty ? "SAMPLE" : lines[index % lines.count],
                latitude: centre.latitude + sample.latitudeOffset,
                longitude: centre.longitude + sample.longitudeOffset,
                destination: nil,
                delay: VehicleDelay(rawMinutes: sample.minutes),
                traction: .bus
            )
        }
        return VehiclePayload(
            vehicles: vehicles,
            skippedRecordCount: 0,
            unlocatableRecordCount: 0
        )
    }
}
#endif
