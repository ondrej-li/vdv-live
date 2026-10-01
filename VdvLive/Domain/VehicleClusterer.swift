import CoreLocation

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
