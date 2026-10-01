import CoreLocation
import Foundation

/// One marker on the map: the vehicles that share a single grid cell.
///
/// The feed is dense enough that drawing every vehicle separately at region
/// zoom produces a wall of overlapping pins, so nearby vehicles are merged into
/// one marker that carries their count.
struct VehicleCluster: Identifiable, Equatable, Sendable {
    /// Position of the cell inside the grid that produced the cluster.
    struct Cell: Hashable, Sendable {
        let row: Int
        let column: Int
    }

    let cell: Cell
    /// Members ordered by server id, so the marker set is stable across
    /// refreshes and SwiftUI can diff it.
    let vehicles: [Vehicle]
    /// Vehicle used to style the marker.
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

    /// Marker identity on the map. Cells are position based, so the identity of
    /// a marker changes when the grid moves, which is exactly what makes the
    /// annotations re-layout instead of drifting when the map is panned.
    var id: String { "\(cell.row):\(cell.column)" }

    var count: Int { vehicles.count }

    /// The single member, `nil` when the cluster merges several vehicles.
    var singleVehicle: Vehicle? { vehicles.count == 1 ? representative : nil }

    init?(
        cell: Cell,
        vehicles: [Vehicle],
        drawnCoordinate: CLLocationCoordinate2D? = nil,
        isStale: Bool = false
    ) {
        guard let first = vehicles.first else { return nil }
        self.cell = cell
        self.vehicles = vehicles
        self.representative = first
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
        lhs.cell == rhs.cell
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
