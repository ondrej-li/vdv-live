import CoreGraphics
import Foundation

/// Length of a scale bar for the current zoom level.
///
/// The map is a Mercator projection, and Mercator is locally square: one point
/// across the screen and one point down cover the same ground distance. So the
/// distance behind a horizontal bar follows from the latitude span MapKit fits
/// into the map's height.
struct MapScale: Equatable, Sendable {
    /// Ground distance the bar stands for.
    let distanceMetres: Double
    /// Length of the bar, in points.
    let barLength: CGFloat

    /// Metres per degree of latitude, near enough anywhere in the region.
    static let metresPerDegreeLatitude: Double = 111_132

    /// Distances worth labelling: round numbers, meters then kilometres.
    static let stepDistances: [Double] = [
        10, 20, 50, 100, 200, 500,
        1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000, 200_000, 500_000
    ]

    /// Scale bar for a map `mapHeight` points tall showing `latitudeSpan` degrees
    /// of latitude, aimed at a bar of roughly `targetLength` points.
    ///
    /// Returns `nil` when the span or the size is not known yet, so callers can
    /// simply skip the legend during the first layout pass.
    static func make(
        latitudeSpan: Double,
        mapHeight: CGFloat,
        targetLength: CGFloat = 88
    ) -> MapScale? {
        guard latitudeSpan > 0, mapHeight > 0, targetLength > 0 else { return nil }

        let metresPerPoint = latitudeSpan / Double(mapHeight) * metresPerDegreeLatitude
        guard metresPerPoint > 0, metresPerPoint.isFinite else { return nil }

        let wanted = metresPerPoint * Double(targetLength)
        let distance = stepDistances.last { $0 <= wanted } ?? stepDistances[0]

        return MapScale(distanceMetres: distance, barLength: CGFloat(distance / metresPerPoint))
    }

    /// `500 m` below a kilometre, `5 km` above it.
    var labelText: String {
        if distanceMetres < 1_000 {
            return String(format: String(localized: "%lld m"), Int(distanceMetres.rounded()))
        }
        return String(format: String(localized: "%lld km"), Int((distanceMetres / 1_000).rounded()))
    }
}
