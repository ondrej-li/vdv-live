import CoreLocation
import Foundation

/// A service the timetable says is out, standing where it should be.
///
/// The feed drops whole lines for stretches of the day. This is what the map
/// draws instead of nothing: not a measurement, not a guess about whereabouts,
/// but the published stop the run is due at, taken from the archive and placed
/// with the stop positions the app already ships.
///
/// It is deliberately not a ``Vehicle``: everything a vehicle knows - a delay, a
/// destination reported by the operator, a position somebody measured - is
/// missing here, and reusing the type would let a calculated marker be drawn,
/// selected or counted as though it were live.
struct ExpectedService: Identifiable, Hashable, Sendable {
    /// Line number the way the feed and the archive both write it: `764337`.
    let lineNumber: String
    /// JDF run number, the feed's `Spoj`.
    let serviceNumber: String
    /// Stop the run is due at, as the timetable names it.
    let stopName: String
    let latitude: Double
    let longitude: Double
    /// When the run is due at ``stopName``, before any delay.
    let scheduledTime: TimeOfDay

    /// One marker per line, so the line is what identifies it.
    var id: String { lineNumber }

    /// Line as a passenger knows it: `337`.
    var displayLine: String { LineCode(raw: lineNumber).number }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
