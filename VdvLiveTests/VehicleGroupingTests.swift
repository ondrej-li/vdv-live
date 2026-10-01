import CoreLocation
import MapKit
import XCTest
@testable import VdvLive

/// What the map does with the grouping radius, and how grouped markers behave
/// between payloads.
@MainActor
final class VehicleGroupingTests: XCTestCase {
    /// Two vehicles about 67 m apart, and one about 1.1 km away.
    private var sampleVehicles: [Vehicle] {
        [
            Fixture.vehicle(id: 1, latitude: 49.4000, longitude: 15.6000),
            Fixture.vehicle(id: 2, latitude: 49.4006, longitude: 15.6000),
            Fixture.vehicle(id: 3, latitude: 49.4100, longitude: 15.6000)
        ]
    }

    private func makeViewModel(
        settings: AppSettings,
        vehicles: [Vehicle] = []
    ) -> (viewModel: VehicleMapViewModel, store: InMemoryAppSettingsStore) {
        let store = InMemoryAppSettingsStore(settings: settings)
        let viewModel = VehicleMapViewModel(
            fetcher: StubVehicleFetcher(vehicles: vehicles),
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: store,
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher()
        )
        return (viewModel, store)
    }

    private func settings(clusterRadiusMetres: Double) -> AppSettings {
        AppSettings(
            autoRefreshInterval: AppSettings.defaultAutoRefreshInterval,
            autoRefreshEnabled: false,
            language: .czech,
            clusterRadiusMetres: clusterRadiusMetres
        )
    }

    // MARK: - The radius

    func testNothingIsGroupedByDefault() {
        let (viewModel, _) = makeViewModel(settings: .default)

        XCTAssertEqual(AppSettings.default.clusterRadiusMetres, 0)
        XCTAssertEqual(viewModel.clusterRadiusMetres, 0)
    }

    func testEveryVehicleGetsAMarkerOfItsOwnWithoutARadius() async {
        let (viewModel, _) = makeViewModel(settings: settings(clusterRadiusMetres: 0), vehicles: sampleVehicles)

        await viewModel.load()

        XCTAssertEqual(viewModel.clusters.count, 3)
        XCTAssertEqual(viewModel.clusters.compactMap { $0.singleVehicle?.id }, [1, 2, 3])
        XCTAssertEqual(viewModel.visibleVehicleCount, 3)
        XCTAssertEqual(viewModel.vehicleCount, 3)
    }

    func testVehiclesWithinTheRadiusShareAMarker() async {
        let (viewModel, _) = makeViewModel(settings: settings(clusterRadiusMetres: 100), vehicles: sampleVehicles)

        await viewModel.load()

        XCTAssertEqual(viewModel.clusters.count, 2)
        XCTAssertEqual(viewModel.clusters.map(\.count), [2, 1])
        XCTAssertEqual(viewModel.visibleVehicleCount, 3)
    }

    func testChangingTheRadiusRebuildsTheMarkersAndIsRemembered() async {
        let (viewModel, store) = makeViewModel(settings: settings(clusterRadiusMetres: 0), vehicles: sampleVehicles)
        await viewModel.load()
        XCTAssertEqual(viewModel.clusters.count, 3)

        viewModel.setClusterRadius(100)

        XCTAssertEqual(viewModel.clusters.count, 2, "the markers change without waiting for a payload")
        XCTAssertEqual(store.load().clusterRadiusMetres, 100)
        XCTAssertEqual(store.saveCount, 1)

        viewModel.setClusterRadius(0)

        XCTAssertEqual(viewModel.clusters.count, 3)
        XCTAssertEqual(store.load().clusterRadiusMetres, 0)
        XCTAssertEqual(store.saveCount, 2)
    }

    func testANegativeRadiusIsStoredAsNoGroupingAtAll() {
        let (viewModel, store) = makeViewModel(settings: settings(clusterRadiusMetres: 100))

        viewModel.setClusterRadius(-50)

        XCTAssertEqual(viewModel.clusterRadiusMetres, 0)
        XCTAssertEqual(store.load().clusterRadiusMetres, 0)
    }

    func testSettingTheSameRadiusAgainIsNotAChange() {
        let (viewModel, store) = makeViewModel(settings: settings(clusterRadiusMetres: 250))

        viewModel.setClusterRadius(250)

        XCTAssertEqual(store.saveCount, 0)
    }

    // MARK: - Static markers

    func testAGroupedMarkerHoldsItsPositionWhileItsMembersMove() async throws {
        // The group is the same two vehicles before and after, so the marker is
        // a place on the map and must not drift with them.
        let fetcher = StubVehicleFetcher(payloads: [
            VehiclePayload(
                vehicles: [
                    Fixture.vehicle(id: 1, latitude: 49.4000, longitude: 15.6000),
                    Fixture.vehicle(id: 2, latitude: 49.4006, longitude: 15.6000)
                ],
                skippedRecordCount: 0,
                unlocatableRecordCount: 0
            ),
            VehiclePayload(
                vehicles: [
                    Fixture.vehicle(id: 1, latitude: 49.4004, longitude: 15.6000),
                    Fixture.vehicle(id: 2, latitude: 49.4009, longitude: 15.6000)
                ],
                skippedRecordCount: 0,
                unlocatableRecordCount: 0
            )
        ])
        let viewModel = VehicleMapViewModel(
            fetcher: fetcher,
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(settings: settings(clusterRadiusMetres: 100)),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher()
        )

        await viewModel.load()
        let before = try XCTUnwrap(viewModel.clusters.first)

        await viewModel.load()
        let after = try XCTUnwrap(viewModel.clusters.first)

        XCTAssertEqual(after.vehicles.map(\.id), before.vehicles.map(\.id), "the group is unchanged")
        XCTAssertEqual(after.drawnCoordinate.latitude, before.drawnCoordinate.latitude, accuracy: 0.0000001)
        XCTAssertNotEqual(
            after.coordinate.latitude,
            before.coordinate.latitude,
            "the members moved, even though the marker did not"
        )
    }

    func testAGroupedMarkerIsPlacedAfreshWhenABusLeavesIt() async throws {
        // The second vehicle stops reporting, so what is left is a group of one
        // - a different marker, placed where its member actually is.
        let fetcher = StubVehicleFetcher(payloads: [
            VehiclePayload(
                vehicles: [
                    Fixture.vehicle(id: 1, latitude: 49.4000, longitude: 15.6000),
                    Fixture.vehicle(id: 2, latitude: 49.4006, longitude: 15.6000)
                ],
                skippedRecordCount: 0,
                unlocatableRecordCount: 0
            ),
            VehiclePayload(
                vehicles: [
                    Fixture.vehicle(id: 1, latitude: 49.4004, longitude: 15.6000),
                    Fixture.vehicle(id: 2, latitude: 49.4006, longitude: 15.6000)
                ],
                skippedRecordCount: 0,
                unlocatableRecordCount: 0
            )
        ])
        let viewModel = VehicleMapViewModel(
            fetcher: fetcher,
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(settings: settings(clusterRadiusMetres: 100)),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher()
        )

        await viewModel.load()
        // The group holds its position while both members are still in it.
        await viewModel.load()
        let held = try XCTUnwrap(viewModel.clusters.first)
        XCTAssertEqual(held.count, 2)
        XCTAssertEqual(held.drawnCoordinate.latitude, 49.4003, accuracy: 0.0000001)

        viewModel.setClusterRadius(0)

        XCTAssertEqual(viewModel.clusters.map(\.id), ["vehicle:1", "vehicle:2"])
        XCTAssertEqual(
            viewModel.clusters.first?.drawnCoordinate.latitude ?? 0,
            49.4004,
            accuracy: 0.0000001
        )
    }

    func testAMarkerForASingleVehicleStillTravels() async throws {
        // Nothing is grouped, so the marker is the bus: it glides to where the
        // feed put it, as it always did.
        let fetcher = StubVehicleFetcher(payloads: [
            VehiclePayload(
                vehicles: [Fixture.vehicle(id: 1, latitude: 49.4000, longitude: 15.6000)],
                skippedRecordCount: 0,
                unlocatableRecordCount: 0
            ),
            VehiclePayload(
                vehicles: [Fixture.vehicle(id: 1, latitude: 49.4100, longitude: 15.6000)],
                skippedRecordCount: 0,
                unlocatableRecordCount: 0
            )
        ])
        let viewModel = VehicleMapViewModel(
            fetcher: fetcher,
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(settings: settings(clusterRadiusMetres: 0)),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(),
            markerMotionDuration: 5
        )

        await viewModel.load()
        let before = try XCTUnwrap(viewModel.clusters.first).drawnCoordinate.latitude
        await viewModel.load()

        let after = try XCTUnwrap(viewModel.clusters.first).drawnCoordinate
        XCTAssertGreaterThanOrEqual(after.latitude, before)
        XCTAssertLessThan(after.latitude, 49.4100, "it is on its way, not teleported")
    }

    // MARK: - Quiet vehicles

    func testQuietVehiclesAreGreyedOneAtATimeWithoutAGroup() async {
        let fetcher = StubVehicleFetcher(payloads: [
            VehiclePayload(vehicles: sampleVehicles, skippedRecordCount: 0, unlocatableRecordCount: 0),
            VehiclePayload(vehicles: [sampleVehicles[2]], skippedRecordCount: 0, unlocatableRecordCount: 0)
        ])
        let viewModel = VehicleMapViewModel(
            fetcher: fetcher,
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(settings: settings(clusterRadiusMetres: 0)),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher()
        )

        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(viewModel.vehicleCount, 1, "the header counts what the feed reports")
        XCTAssertEqual(viewModel.visibleVehicleCount, 3, "the quiet ones stay on the map")
        XCTAssertEqual(viewModel.clusters.filter(\.isStale).count, 2)
    }
}
