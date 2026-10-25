import CoreLocation

/// Whether the map is turned away from north.
///
/// The compass is drawn only while the map is turned, so this is what decides whether
/// a button exists at all. A heading is an angle round a circle, not a number on a
/// line: 359.5° is half a degree from north, not 359.5 of them, and comparing it the
/// naive way would leave the compass on screen forever.
enum MapHeading {
    /// How far from north still counts as north-up, in degrees. Wider than the compass
    /// needle's own jitter, narrower than anything a finger can do on purpose.
    static let tolerance: CLLocationDirection = 1

    static func isTurnedAwayFromNorth(_ heading: CLLocationDirection) -> Bool {
        guard heading.isFinite else { return false }
        let normalized = heading.truncatingRemainder(dividingBy: 360)
        let distance = min(abs(normalized), 360 - abs(normalized))
        return distance > tolerance
    }
}
