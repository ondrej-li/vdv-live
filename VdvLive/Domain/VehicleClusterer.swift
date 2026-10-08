import CoreLocation
import MapKit

/// Groups vehicles that are close together into one marker.
///
/// A group is built around an anchor: the lowest numbered vehicle in it is the one
/// the others are measured against. That makes the grouping depend on the payload
/// alone rather than on the order the feed happened to send it in, and it gives
/// every group a stable identity - its anchor - which is what lets a marker keep
/// the position it is drawn at between refreshes.
enum VehicleClusterer {
    /// Markers for the vehicles on screen, ordered by their anchor.
    ///
    /// A radius of zero leaves every vehicle on its own. Above that, a vehicle
    /// joins the first group whose anchor is within `radiusMetres`, and starts a
    /// group of its own when there is none.
    static func markers(
        _ vehicles: [Vehicle],
        in viewport: RegionOfInterest.BoundingBox,
        radiusMetres: Double
    ) -> [VehicleCluster] {
        let visible = vehicles
            .filter { viewport.contains($0.coordinate) }
            .sorted { $0.id < $1.id }

        guard radiusMetres > 0 else {
            return visible.compactMap { VehicleCluster(vehicle: $0) }
        }

        var groups: [Group] = []
        for vehicle in visible {
            if let index = groups.firstIndex(where: { $0.holds(vehicle, radiusMetres: radiusMetres) }) {
                groups[index].members.append(vehicle)
            } else {
                groups.append(Group(anchor: vehicle))
            }
        }

        return groups.compactMap { VehicleCluster(group: $0.members) }
    }

    /// The number of vehicles on the map above which it stops drawing every one of
    /// them as its own marker.
    ///
    /// Measured on a Mac showing the whole region: 610 vehicles cost 0.83 s of CPU in
    /// the five seconds after launch, against 0.25 s for the ten markers of a
    /// favourites-only map - and that was before any panning.
    static let crowdingThreshold = 100

    /// How far apart two vehicles have to be when the map is crowded, as a fraction
    /// of the visible span.
    ///
    /// A fraction of the span rather than a distance in metres, so that it is the
    /// same number of pixels at every zoom: a fortieth of the span is about 25 px on
    /// a desktop window, which is the size of a marker. Markers that overlap are what
    /// makes a crowd both expensive to draw and impossible to read.
    static let crowdedSpanFraction = 1.0 / 40

    /// The radius to group markers with.
    ///
    /// The setting - "Group buses within" - is in metres, and stops meaning anything
    /// at region zoom: a hundred metres is well under a pixel there, so all 610
    /// vehicles stay their own marker and the map lays every one of them out again
    /// whenever it moves. Above ``crowdingThreshold`` vehicles the wider of the two is
    /// used instead. Below it the setting is left exactly as it is, so a map of the
    /// user's own lines behaves as it always has.
    static func groupingRadiusMetres(
        setting: Double,
        vehicles: Int,
        span: MKCoordinateSpan
    ) -> Double {
        guard vehicles > crowdingThreshold else { return setting }
        let crowded = span.latitudeDelta * MapScale.metresPerDegreeLatitude * crowdedSpanFraction
        return max(setting, crowded)
    }

    /// Distance between two coordinates, in metres.
    ///
    /// Flat earth arithmetic, which is plenty for a radius of a few hundred
    /// metres: over that distance the error in treating the globe as a plane is
    /// far smaller than a bus.
    static func metres(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let latitudeMetres = (to.latitude - from.latitude) * MapScale.metresPerDegreeLatitude
        let longitudeMetres = (to.longitude - from.longitude)
            * MapRegion.metresPerDegreeLongitude(at: from.latitude)
        return (latitudeMetres * latitudeMetres + longitudeMetres * longitudeMetres).squareRoot()
    }

    /// A group being built: the vehicles gathered so far, and the anchor they
    /// were measured against.
    private struct Group {
        let anchor: Vehicle
        var members: [Vehicle]

        init(anchor: Vehicle) {
            self.anchor = anchor
            self.members = [anchor]
        }

        /// Whether `vehicle` is close enough to the anchor to join.
        func holds(_ vehicle: Vehicle, radiusMetres: Double) -> Bool {
            metres(from: anchor.coordinate, to: vehicle.coordinate) <= radiusMetres
        }

        private func metres(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
            VehicleClusterer.metres(from: from, to: to)
        }
    }
}
