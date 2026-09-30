import CoreLocation
import Foundation

/// A single vehicle position as published by the regional feed.
struct Vehicle: Identifiable, Hashable, Sendable {
    /// Server side identifier, unique within one response. Trains and vehicles
    /// that are not part of the public timetable carry negative ids.
    let id: Int
    /// Line number / connection designation, e.g. `841334`.
    let line: String
    let latitude: Double
    let longitude: Double
    /// Final stop as reported by the feed, `nil` when the feed only sent its
    /// `-1 N/a` placeholder.
    let destination: String?
    let delay: VehicleDelay
    let traction: Traction

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The feed's line code, with the operator prefix separated out.
    var lineCode: LineCode { LineCode(raw: line) }

    /// Line as shown to passengers, e.g. `337` rather than `764337`.
    var displayLine: String { lineCode.number }

    /// Whether the position is worth putting on a map.
    ///
    /// The feed publishes vehicles it cannot place as `lat: 0, lng: 0`, which
    /// would otherwise land in the Gulf of Guinea.
    var isLocatable: Bool {
        guard latitude != 0 || longitude != 0 else { return false }
        return CLLocationCoordinate2DIsValid(coordinate)
    }
}
