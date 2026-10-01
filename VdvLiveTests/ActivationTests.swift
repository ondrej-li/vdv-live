import Foundation
import XCTest
@testable import VdvLive

/// What the map does when the app comes back to the screen.
///
/// The positions on screen were fetched before the app went away, and iOS
/// suspends the automatic refresh while it is in the background, so on the way
/// back they are greyed and replaced rather than left looking current.
@MainActor
final class ActivationTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private var sampleVehicles: [Vehicle] {
        [
            Fixture.vehicle(id: 1, latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, latitude: 49.3961, longitude: 15.5911),
            Fixture.vehicle(id: 3, latitude: 49.6070, longitude: 15.5810, traction: .train)
        ]
    }

    /// View model with automatic refresh off, so that a test only sees the
    /// fetches it asked for.
    private func makeViewModel(
        vehicles: [Vehicle],
        error: Error? = nil
    ) -> (viewModel: VehicleMapViewModel, fetcher: StubVehicleFetcher) {
        let fetcher = StubVehicleFetcher(vehicles: vehicles, error: error)
        let referenceDate = self.referenceDate
        let viewModel = VehicleMapViewModel(
            payloadStore: InMemoryVehiclePayloadStore(),
            fetcher: fetcher,
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(
                settings: AppSettings(
                    autoRefreshInterval: AppSettings.defaultAutoRefreshInterval,
                    autoRefreshEnabled: false,
                    language: .czech,
                    clusterRadiusMetres: 0
                )
            ),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(),
            now: { referenceDate }
        )
        return (viewModel, fetcher)
    }

    func testComingBackGreysEveryMarkerBeforeAnythingIsFetched() async {
        let (viewModel, fetcher) = makeViewModel(vehicles: sampleVehicles)
        await viewModel.load()
        XCTAssertFalse(viewModel.clusters.contains { $0.isStale })

        viewModel.markPayloadStale()

        XCTAssertTrue(viewModel.clusters.allSatisfy(\.isStale))
        XCTAssertEqual(viewModel.clusters.count, 3, "grey, not gone")
        XCTAssertEqual(fetcher.callCount, 1, "the grey must not wait for a request")
    }

    func testComingBackFetchesStraightAway() async {
        let (viewModel, fetcher) = makeViewModel(vehicles: sampleVehicles)
        await viewModel.load()

        await viewModel.appDidBecomeActive()

        XCTAssertEqual(fetcher.callCount, 2, "the refresh interval is not waited for")
    }

    func testThePayloadThatArrivesClearsTheGrey() async {
        let (viewModel, fetcher) = makeViewModel(vehicles: sampleVehicles)
        await viewModel.load()
        viewModel.markPayloadStale()

        await viewModel.appDidBecomeActive()

        XCTAssertEqual(fetcher.callCount, 2)
        XCTAssertFalse(viewModel.clusters.contains { $0.isStale })
    }

    func testTheGreyIsClearedPerMarkerByItsNextPayload() async {
        // A bus that has gone missing stays grey once the map is current again:
        // greying the whole map must not un-grey a vehicle the feed dropped.
        let (viewModel, fetcher) = makeViewModel(vehicles: sampleVehicles)
        await viewModel.load()
        fetcher.payloads = [
            VehiclePayload(
                vehicles: [sampleVehicles[0], sampleVehicles[1]],
                skippedRecordCount: 0,
                unlocatableRecordCount: 0
            )
        ]
        await viewModel.load()  // vehicle 3 goes missing once
        viewModel.markPayloadStale()

        await viewModel.appDidBecomeActive()

        let staleIDs = viewModel.clusters.filter(\.isStale).flatMap { $0.vehicles.map(\.id) }
        XCTAssertEqual(staleIDs, [3], "only the vehicle that is not being reported")
    }

    func testAPayloadThatFailsLeavesTheMapGrey() async {
        let (viewModel, fetcher) = makeViewModel(vehicles: sampleVehicles)
        await viewModel.load()
        fetcher.error = URLError(.notConnectedToInternet)

        await viewModel.appDidBecomeActive()

        XCTAssertTrue(viewModel.clusters.allSatisfy(\.isStale))
        XCTAssertNotNil(viewModel.errorMessage, "so is the reason")
        XCTAssertEqual(viewModel.vehicleCount, 3, "the old positions are kept, greyed")
    }

    func testALaunchIsNotTreatedAsAReturn() async {
        let (viewModel, fetcher) = makeViewModel(vehicles: sampleVehicles)

        await viewModel.appDidBecomeActive()

        XCTAssertEqual(fetcher.callCount, 0, "the launch fetch is the view's own")
        XCTAssertTrue(viewModel.clusters.isEmpty)
    }
}
