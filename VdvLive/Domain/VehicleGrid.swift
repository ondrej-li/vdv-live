import CoreLocation
import MapKit

/// The grid used to group nearby vehicles into a single marker.
///
/// The grid is derived from the visible map region: the same vehicles are
/// grouped coarsely while zoomed out and split apart as the user zooms in.
/// Bounding the grid also bounds the number of markers SwiftUI has to lay out
/// at once, which keeps the map responsive with a few hundred vehicles.
struct VehicleGrid: Hashable, Sendable {
    static let defaultGridSize = 10

    let gridSize: Int
    let minLatitude: Double
    let minLongitude: Double
    let latitudeStep: Double
    let longitudeStep: Double

    init(region: MKCoordinateRegion, gridSize: Int = VehicleGrid.defaultGridSize) {
        let size = max(1, gridSize)
        let latitudeSpan = region.span.latitudeDelta
        let longitudeSpan = region.span.longitudeDelta
        self.gridSize = size
        self.latitudeStep = Self.usableStep(latitudeSpan / Double(size))
        self.longitudeStep = Self.usableStep(longitudeSpan / Double(size))
        self.minLatitude = region.center.latitude - latitudeSpan / 2
        self.minLongitude = region.center.longitude - longitudeSpan / 2
    }

    /// Cell a coordinate falls into, clamped so that a point sitting exactly on
    /// the far edge of the region stays inside the grid.
    func cell(for coordinate: CLLocationCoordinate2D) -> VehicleCluster.Cell {
        VehicleCluster.Cell(
            row: index(of: coordinate.latitude, origin: minLatitude, step: latitudeStep),
            column: index(of: coordinate.longitude, origin: minLongitude, step: longitudeStep)
        )
    }

    func contains(_ vehicle: Vehicle) -> Bool {
        contains(latitude: vehicle.latitude, longitude: vehicle.longitude)
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        let maxLatitude = minLatitude + latitudeStep * Double(gridSize)
        let maxLongitude = minLongitude + longitudeStep * Double(gridSize)
        return (minLatitude...maxLatitude).contains(latitude)
            && (minLongitude...maxLongitude).contains(longitude)
    }

    private func index(of value: Double, origin: Double, step: Double) -> Int {
        let raw = ((value - origin) / step).rounded(.down)
        guard raw.isFinite else { return 0 }
        let clamped = min(max(raw, 0), Double(gridSize - 1))
        return Int(clamped)
    }

    private static func usableStep(_ step: Double) -> Double {
        guard step.isFinite, step > 0 else { return .leastNonzeroMagnitude }
        return step
    }
}
