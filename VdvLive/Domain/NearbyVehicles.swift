import CoreLocation
import Foundation

/// A vehicle of a pinned line, with how far it is from the reader.
struct NearbyVehicle: Identifiable, Hashable, Sendable {
    let vehicle: Vehicle
    /// Straight-line distance from the reader, not the length of the journey.
    let distanceMetres: Double

    var id: Int { vehicle.id }
}

/// The vehicles of the pinned lines that are near the reader.
///
/// The widget asks a smaller question than the map does: not "what is running"
/// but "what of mine is close". Pinning a line is the user saying they care
/// about it, so this never widens to other lines however empty the answer is -
/// an empty list is a true answer, and the widget says so.
enum NearbyVehicles {
    /// How far out a vehicle counts as being around the reader.
    ///
    /// Ten kilometres, the size of the neighbourhood the map opens on, which is
    /// the distance at which a bus is worth walking to.
    static let radiusMetres: Double = 10_000

    /// How many vehicles a widget can show without becoming a list to scroll.
    static let limit = 4

    /// The pinned lines' vehicles within `radiusMetres` of `coordinate`, nearest
    /// first.
    ///
    /// Without a position there is no "near", so the answer is empty rather than
    /// the whole region: the widget shows a message instead of pretending to know
    /// where the reader is.
    static func nearby(in vehicles: [Vehicle],
                       pinnedTo lines: FavouriteLines,
                       from coordinate: CLLocationCoordinate2D?,
                       radiusMetres: Double = NearbyVehicles.radiusMetres,
                       limit: Int = NearbyVehicles.limit) -> [NearbyVehicle] {
        guard let coordinate, !lines.isEmpty, limit > 0 else { return [] }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return vehicles
            .compactMap { vehicle -> NearbyVehicle? in
                guard vehicle.isLocatable, lines.contains(vehicle.line) else { return nil }
                let position = CLLocation(latitude: vehicle.latitude, longitude: vehicle.longitude)
                let distance = origin.distance(from: position)
                guard distance <= radiusMetres else { return nil }
                return NearbyVehicle(vehicle: vehicle, distanceMetres: distance)
            }
            .sorted { first, second in
                if first.distanceMetres != second.distanceMetres {
                    return first.distanceMetres < second.distanceMetres
                }
                return FavouriteLines.isOrderedBefore(FavouriteLines.normalize(first.vehicle.line),
                                                      FavouriteLines.normalize(second.vehicle.line))
            }
            .prefix(limit)
            .map { $0 }
    }
}
