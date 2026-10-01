import CoreLocation
import Foundation

/// One stop of the run a vehicle is currently serving.
struct RunStop: Hashable, Sendable {
    let name: String
    /// Timetable time, as the feed formats it (`14:12`), `nil` when the stop is
    /// only a request stop with no time.
    let arrival: String?
    let departure: String?
}

/// Everything the map's own detail popup knows about a vehicle.
///
/// Comes from `/Ajax/OpenInfoWindow` (line, service, stop, barrier-free flag)
/// and `/Ajax/GetTimetable` (the stop list of the current run), neither of
/// which is part of the points feed.
struct VehicleDetail: Equatable, Sendable {
    /// Line as the feed's detail page reports it, licence area prefix included.
    let lineCode: LineCode
    /// `Spoj`: which run of the line this is, e.g. the 11th service of the day.
    let serviceNumber: String?
    let isBarrierFree: Bool?
    /// `Zastávka`: the stop the vehicle is serving, as reported by the feed.
    let stopName: String?
    let reportedDelayMinutes: Int?
    /// Stops of the current run, in order.
    let runStops: [RunStop]

    /// The reported stop, matched against the run's stop list.
    var stop: RunStop? {
        guard let stopName, !stopName.isEmpty else { return nil }
        return runStops.first { $0.name == stopName }
    }

    /// The stop the vehicle is heading to after ``stop``.
    var nextStop: RunStop? {
        guard
            let stop,
            let index = runStops.firstIndex(of: stop),
            runStops.indices.contains(index + 1)
        else {
            return nil
        }
        return runStops[index + 1]
    }

    /// Line number with the licence area prefix taken off.
    var lineNumber: String { lineCode.number }
}

extension RunStop {
    /// Time shown next to a stop: the departure when there is one, otherwise
    /// the arrival.
    var timeText: String? { departure ?? arrival }
}
