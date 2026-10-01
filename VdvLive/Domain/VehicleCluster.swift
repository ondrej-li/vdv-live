import CoreLocation
import Foundation

/// One marker on the map: either one vehicle, or several close enough together to
/// be drawn as a group.
///
/// The feed is dense enough that drawing every vehicle separately at region zoom
/// produces a wall of overlapping pins, so vehicles can be grouped into one marker
/// that carries their count. How close they have to be is a setting, and at zero
/// every vehicle gets a marker of its own.
struct VehicleCluster: Identifiable, Equatable, Sendable {
    /// Identity of the marker, which the map diffs on.
    ///
    /// A marker standing for one vehicle is identified by that vehicle, and a
    /// group by its anchor. Either way the identity survives a refresh for as long
    /// as the marker stands for the same vehicles, which is what lets it keep the
    /// position it was drawn at.
    let id: String
    /// Members ordered by server id, so the marker set is stable across
    /// refreshes and SwiftUI can diff it.
    let vehicles: [Vehicle]
    /// Vehicle used to style the marker: for a group, its anchor, which is the
    /// lowest numbered vehicle in it.
    let representative: Vehicle
    /// Where the marker is drawn right now.
    ///
    /// It starts at ``coordinate`` and is walked towards the next payload's
    /// ``coordinate`` by the view model, so that a refresh moves a vehicle
    /// instead of teleporting it. Stored rather than computed on purpose:
    /// SwiftUI's `Map` only applies a new position when the annotation it was
    /// built from has changed, so the position a marker is drawn at has to be
    /// part of the marker.
    var drawnCoordinate: CLLocationCoordinate2D
    /// True when the feed has not mentioned any of these vehicles for one or more
    /// payloads. The marker stays where it was last seen, drawn grey, until the
    /// view model decides the vehicle is gone for good.
    var isStale: Bool

    var count: Int { vehicles.count }

    /// The single member, `nil` when the cluster merges several vehicles.
    var singleVehicle: Vehicle? { vehicles.count == 1 ? representative : nil }

    /// Marker for a single vehicle, used when nothing is being grouped.
    init?(
        vehicle: Vehicle,
        drawnCoordinate: CLLocationCoordinate2D? = nil,
        isStale: Bool = false
    ) {
        self.init(
            id: "vehicle:\(vehicle.id)",
            vehicles: [vehicle],
            drawnCoordinate: drawnCoordinate,
            isStale: isStale
        )
    }

    /// Marker for vehicles drawn together.
    ///
    /// The first is the anchor the group was built around: it names the marker
    /// and is the vehicle used to style it.
    init?(
        group: [Vehicle],
        drawnCoordinate: CLLocationCoordinate2D? = nil,
        isStale: Bool = false
    ) {
        guard let anchor = group.first else { return nil }
        self.init(
            id: "cluster:\(anchor.id)",
            vehicles: group,
            drawnCoordinate: drawnCoordinate,
            isStale: isStale
        )
    }

    private init(
        id: String,
        vehicles: [Vehicle],
        drawnCoordinate: CLLocationCoordinate2D?,
        isStale: Bool
    ) {
        self.id = id
        self.vehicles = vehicles
        self.representative = vehicles[0]
        self.drawnCoordinate = drawnCoordinate ?? Self.position(of: vehicles)
        self.isStale = isStale
    }

    /// Position of the marker: the exact position for a single vehicle, the
    /// average position of the members otherwise.
    var coordinate: CLLocationCoordinate2D { Self.position(of: vehicles) }

    static func position(of vehicles: [Vehicle]) -> CLLocationCoordinate2D {
        guard let first = vehicles.first else { return CLLocationCoordinate2D() }
        guard vehicles.count > 1 else {
            return CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
        }
        let count = Double(vehicles.count)
        return CLLocationCoordinate2D(
            latitude: vehicles.reduce(0) { $0 + $1.latitude } / count,
            longitude: vehicles.reduce(0) { $0 + $1.longitude } / count
        )
    }

    static func == (lhs: VehicleCluster, rhs: VehicleCluster) -> Bool {
        lhs.id == rhs.id
            && lhs.vehicles == rhs.vehicles
            && lhs.isStale == rhs.isStale
            && lhs.drawnCoordinate.latitude == rhs.drawnCoordinate.latitude
            && lhs.drawnCoordinate.longitude == rhs.drawnCoordinate.longitude
    }

    /// Traction with the most members, used to colour the marker.
    var dominantTraction: Traction {
        var counts: [Traction: Int] = [:]
        for vehicle in vehicles {
            counts[vehicle.traction, default: 0] += 1
        }
        let best = counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key.sortIndex > rhs.key.sortIndex
        }
        return best?.key ?? representative.traction
    }

    /// Voice over label and detail card title.
    var title: String {
        if let vehicle = singleVehicle {
            return String(format: String(localized: "Line %@"), vehicle.displayLine)
        }
        return String(format: String(localized: "%lld vehicles"), count)
    }
}
