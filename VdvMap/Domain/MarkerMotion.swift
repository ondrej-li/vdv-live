import CoreLocation
import Foundation

/// Moves markers from where they were drawn to where a new payload puts them.
///
/// Vehicles are only reported once per refresh, so without this every marker
/// would teleport a few hundred metres every fifteen seconds. Only the two
/// positions are known, so a marker travels the straight line between them at a
/// constant speed.
enum MarkerMotion {
    /// Position between `start` and `end` at `progress`: 0 is the start, 1 the
    /// end, and the speed in between is even. Clamped, so a caller cannot
    /// overshoot either end.
    static func position(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        progress: Double
    ) -> CLLocationCoordinate2D {
        let progress = min(max(progress, 0), 1)
        return CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * progress,
            longitude: start.longitude + (end.longitude - start.longitude) * progress
        )
    }

    /// Whether a marker moved enough to be worth animating. Roughly a metre:
    /// below that the movement is invisible at every zoom level the app allows.
    static func hasMoved(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Bool {
        let threshold = 0.00001
        return abs(end.latitude - start.latitude) > threshold
            || abs(end.longitude - start.longitude) > threshold
    }
}
