import MapKit
import XCTest
@testable import VdvLive

final class VehicleGridTests: XCTestCase {
    private let grid = VehicleGrid(region: Fixture.squareRegion, gridSize: 4)

    func testSplitsTheRegionIntoEqualSteps() {
        XCTAssertEqual(grid.latitudeStep, 0.25, accuracy: 0.0000001)
        XCTAssertEqual(grid.longitudeStep, 0.25, accuracy: 0.0000001)
        XCTAssertEqual(grid.minLatitude, 48.9, accuracy: 0.0000001)
        XCTAssertEqual(grid.minLongitude, 15.1, accuracy: 0.0000001)
    }

    func testPlacesNeighbouringVehiclesInTheSameCell() {
        let first = grid.cell(for: CLLocationCoordinate2D(latitude: 48.95, longitude: 15.15))
        let second = grid.cell(for: CLLocationCoordinate2D(latitude: 48.96, longitude: 15.16))

        XCTAssertEqual(first, second)
    }

    func testPlacesDistantVehiclesInDifferentCells() {
        let southWest = grid.cell(for: CLLocationCoordinate2D(latitude: 48.95, longitude: 15.15))
        let northEast = grid.cell(for: CLLocationCoordinate2D(latitude: 49.16, longitude: 15.36))

        XCTAssertNotEqual(southWest, northEast)
        XCTAssertEqual(northEast, VehicleCluster.Cell(row: 1, column: 1))
    }

    func testClampsCoordinatesBeyondTheRegionIntoTheLastCell() {
        let cell = grid.cell(for: CLLocationCoordinate2D(latitude: 49.95, longitude: 16.2))

        XCTAssertEqual(cell, VehicleCluster.Cell(row: 3, column: 3))
    }

    func testKnowsWhichVehiclesAreInsideTheRegion() {
        XCTAssertTrue(grid.contains(Fixture.vehicle(id: 1, latitude: 49.4, longitude: 15.6)))
        XCTAssertFalse(grid.contains(Fixture.vehicle(id: 2, latitude: 50.5, longitude: 15.6)))
        XCTAssertFalse(grid.contains(Fixture.vehicle(id: 3, latitude: 49.4, longitude: 14.0)))
    }

    func testGridsDerivedFromDifferentRegionsAreNotEqual() {
        let other = VehicleGrid(
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 49.4, longitude: 15.6),
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            ),
            gridSize: 4
        )

        XCTAssertNotEqual(grid, other)
    }

    func testDegenerateRegionStillProducesUsableSteps() {
        let degenerate = VehicleGrid(
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 49.4, longitude: 15.6),
                span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)
            ),
            gridSize: 4
        )

        XCTAssertGreaterThan(degenerate.latitudeStep, 0)
        XCTAssertGreaterThan(degenerate.longitudeStep, 0)
    }
}

final class VehicleGridClustererTests: XCTestCase {
    private let clusterer = VehicleGridClusterer(gridSize: 4)
    private let grid = VehicleGrid(region: Fixture.squareRegion, gridSize: 4)

    func testMergesVehiclesThatShareACell() {
        let vehicles = [
            Fixture.vehicle(id: 1, latitude: 48.95, longitude: 15.15),
            Fixture.vehicle(id: 2, latitude: 48.96, longitude: 15.16),
            Fixture.vehicle(id: 3, latitude: 49.16, longitude: 15.36)
        ]

        let clusters = clusterer.cluster(vehicles, grid: grid)

        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.map(\.count), [2, 1])
        XCTAssertEqual(clusters.first?.vehicles.map(\.id), [1, 2])
    }

    func testLeavesOutVehiclesOutsideTheVisibleRegion() {
        let vehicles = [
            Fixture.vehicle(id: 1, latitude: 49.4, longitude: 15.6),
            Fixture.vehicle(id: 2, latitude: 50.5, longitude: 15.6),
            Fixture.vehicle(id: 3, latitude: 49.4, longitude: 14.0)
        ]

        let clusters = clusterer.cluster(vehicles, grid: grid)

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.vehicles.map(\.id), [1])
    }

    func testMarkerUsesTheAveragePositionOfItsMembers() throws {
        let vehicles = [
            Fixture.vehicle(id: 1, latitude: 48.95, longitude: 15.15),
            Fixture.vehicle(id: 2, latitude: 48.96, longitude: 15.16)
        ]

        let cluster = try XCTUnwrap(clusterer.cluster(vehicles, grid: grid).first)

        XCTAssertEqual(cluster.coordinate.latitude, 48.955, accuracy: 0.0000001)
        XCTAssertEqual(cluster.coordinate.longitude, 15.155, accuracy: 0.0000001)
    }

    func testMarkerOfASingleVehicleKeepsItsExactPosition() throws {
        let vehicles = [Fixture.vehicle(id: 1, latitude: 48.95, longitude: 15.15)]

        let cluster = try XCTUnwrap(clusterer.cluster(vehicles, grid: grid).first)

        XCTAssertEqual(cluster.coordinate.latitude, 48.95, accuracy: 0.0000001)
        XCTAssertEqual(cluster.singleVehicle?.id, 1)
        // 841334 is operator 841 running line 334.
        XCTAssertEqual(cluster.title, String(format: String(localized: "Line %@"), "334"))
    }

    func testOrdersMarkersByCellSoTheMapDoesNotFlicker() {
        let vehicles = [
            Fixture.vehicle(id: 1, latitude: 49.16, longitude: 15.36),
            Fixture.vehicle(id: 2, latitude: 48.95, longitude: 15.15),
            Fixture.vehicle(id: 3, latitude: 48.95, longitude: 15.16)
        ]

        let clusters = clusterer.cluster(vehicles, grid: grid)

        XCTAssertEqual(clusters.map { [$0.cell.row, $0.cell.column] }, [[0, 0], [1, 1]])
    }

    func testDominantTractionWinsOnCountAndBreaksTiesDeterministically() {
        let buses = [
            Fixture.vehicle(id: 1, latitude: 49.4, longitude: 15.6, traction: .bus),
            Fixture.vehicle(id: 2, latitude: 49.4, longitude: 15.6, traction: .bus),
            Fixture.vehicle(id: 3, latitude: 49.4, longitude: 15.6, traction: .train)
        ]
        XCTAssertEqual(clusterer.cluster(buses, grid: grid).first?.dominantTraction, .bus)

        let tie = [
            Fixture.vehicle(id: 4, latitude: 49.4, longitude: 15.6, traction: .train),
            Fixture.vehicle(id: 5, latitude: 49.4, longitude: 15.6, traction: .bus)
        ]
        XCTAssertEqual(clusterer.cluster(tie, grid: grid).first?.dominantTraction, .bus)
    }

    func testMergedMarkerDescribesHowManyVehiclesItStandsFor() throws {
        let vehicles = [
            Fixture.vehicle(id: 1, latitude: 49.4, longitude: 15.6),
            Fixture.vehicle(id: 2, latitude: 49.4, longitude: 15.6)
        ]

        let cluster = try XCTUnwrap(clusterer.cluster(vehicles, grid: grid).first)

        XCTAssertEqual(cluster.title, String(format: String(localized: "%lld vehicles"), 2))
        XCTAssertNil(cluster.singleVehicle)
    }

    func testNumberOfMarkersIsBoundedByTheGrid() {
        let vehicles = (0..<500).map { index in
            Fixture.vehicle(
                id: index,
                latitude: 48.9 + Double(index % 100) * 0.001,
                longitude: 15.1 + Double(index / 100) * 0.001
            )
        }

        let clusters = clusterer.cluster(vehicles, grid: grid)

        XCTAssertLessThanOrEqual(clusters.count, 16)
        XCTAssertEqual(clusters.reduce(0) { $0 + $1.count }, vehicles.count)
    }

    func testEveryVisibleVehicleEndsUpInExactlyOneMarker() {
        let vehicles = (0..<50).map { index in
            Fixture.vehicle(id: index, latitude: 49.0 + Double(index) * 0.01, longitude: 15.2)
        }

        let clusters = clusterer.cluster(vehicles, grid: grid)
        let clusteredIDs = clusters.flatMap { $0.vehicles.map(\.id) }.sorted()

        XCTAssertEqual(clusteredIDs, vehicles.map(\.id).sorted())
    }
}
