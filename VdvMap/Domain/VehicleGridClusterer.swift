import MapKit

/// Turns a list of vehicles into the markers shown on the map.
///
/// Pure value logic: it only needs the visible region, which makes the grouping
/// rules straightforward to test without a map view.
struct VehicleGridClusterer: Sendable {
    let gridSize: Int

    init(gridSize: Int = VehicleGrid.defaultGridSize) {
        self.gridSize = gridSize
    }

    func grid(for region: MKCoordinateRegion) -> VehicleGrid {
        VehicleGrid(region: region, gridSize: gridSize)
    }

    /// Vehicles outside `grid` are left out: they are not on screen, so they
    /// are not part of any marker.
    func cluster(_ vehicles: [Vehicle], grid: VehicleGrid) -> [VehicleCluster] {
        var buckets: [VehicleCluster.Cell: [Vehicle]] = [:]
        for vehicle in vehicles where grid.contains(vehicle) {
            buckets[grid.cell(for: vehicle.coordinate), default: []].append(vehicle)
        }

        var clusters: [VehicleCluster] = []
        clusters.reserveCapacity(buckets.count)
        for (cell, members) in buckets {
            guard let cluster = VehicleCluster(cell: cell, vehicles: members.sorted { $0.id < $1.id }) else {
                continue
            }
            clusters.append(cluster)
        }

        clusters.sort { lhs, rhs in
            if lhs.cell.row != rhs.cell.row {
                return lhs.cell.row < rhs.cell.row
            }
            return lhs.cell.column < rhs.cell.column
        }
        return clusters
    }
}
