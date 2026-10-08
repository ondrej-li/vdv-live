import MapKit

/// How the watch's digital crown maps onto the map's span.
///
/// The crown reports a value from zero to one; the span grows geometrically between
/// the two limits, so a turn of the crown changes the scale by the same proportion
/// wherever you are rather than by the same number of degrees. That is what makes
/// the crown feel the same zooming into a village as zooming into the region.
enum MapZoom {
    /// The closest the crown goes, about four hundred metres across.
    static let closestLatitudeDelta = 0.004
    /// The furthest, which is the whole region and a little beyond it.
    static let widestLatitudeDelta = 1.5
    /// Where the map opens: near enough to the region's own span that the first
    /// turn of the crown does not jump.
    static let initialCrownValue = 0.95

    /// The window to show for a crown value, clamped to the range the crown reports.
    static func span(forCrownValue value: Double) -> MKCoordinateSpan {
        let clamped = min(max(value, 0), 1)
        let latitudeDelta = closestLatitudeDelta
            * pow(widestLatitudeDelta / closestLatitudeDelta, clamped)
        return MKCoordinateSpan(
            latitudeDelta: latitudeDelta,
            longitudeDelta: latitudeDelta * 1.5
        )
    }

    /// The crown value that shows a window `latitudeDelta` degrees tall.
    ///
    /// The inverse of ``span(forCrownValue:)``, for a camera moved by something
    /// other than the crown - a double tap asking for a window of a known size. The
    /// crown is then left where that move left the map instead of jumping back to
    /// the zoom it was at before the next turn.
    static func crownValue(forLatitudeDelta latitudeDelta: Double) -> Double {
        let clamped = min(max(latitudeDelta, closestLatitudeDelta), widestLatitudeDelta)
        return log(clamped / closestLatitudeDelta) / log(widestLatitudeDelta / closestLatitudeDelta)
    }
}
