import XCTest
@testable import VdvLive

/// What the map does when the feed cannot be reached.
///
/// The feed is live data, so an unreachable feed is not the same as a broken
/// answer: the last known positions stay on the map, marked, and the screen says
/// which state the app is in rather than leaving the user to guess why nothing is
/// changing.
@MainActor
final class OfflineTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private var sampleVehicles: [Vehicle] {
        [
            Fixture.vehicle(id: 1, latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, latitude: 49.6070, longitude: 15.5810, traction: .train)
        ]
    }

    /// View model with automatic refresh off, so a test only sees the loads it
    /// asked for, and with the payload store handed back for inspection.
    private func makeViewModel(
        payloadStore: InMemoryVehiclePayloadStore,
        vehicles: [Vehicle] = [],
        error: Error? = nil
    ) -> (viewModel: VehicleMapViewModel, fetcher: StubVehicleFetcher) {
        let fetcher = StubVehicleFetcher(vehicles: vehicles, error: error)
        let referenceDate = self.referenceDate
        let viewModel = VehicleMapViewModel(
            payloadStore: payloadStore,
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

    /// A store holding what a previous launch fetched, an hour before this one.
    private func makeStoreFromLastLaunch(_ vehicles: [Vehicle]) -> InMemoryVehiclePayloadStore {
        InMemoryVehiclePayloadStore(
            stored: StoredVehiclePayload(
                payload: VehiclePayload(
                    vehicles: vehicles,
                    skippedRecordCount: 0,
                    unlocatableRecordCount: 0
                ),
                fetchedAt: referenceDate.addingTimeInterval(-3_600)
            )
        )
    }

    func testAColdStartShowsWhatTheLastLaunchLeft() {
        let store = makeStoreFromLastLaunch(sampleVehicles)

        let (viewModel, fetcher) = makeViewModel(payloadStore: store)

        XCTAssertEqual(fetcher.callCount, 0, "nothing is fetched until the view asks")
        XCTAssertEqual(viewModel.clusters.count, 2)
        XCTAssertEqual(
            viewModel.lastUpdatedAt,
            referenceDate.addingTimeInterval(-3_600),
            "the age of what is on screen is the point"
        )
    }

    func testAPayloadFromTheLastLaunchIsDrawnGrey() {
        let store = makeStoreFromLastLaunch(sampleVehicles)

        let (viewModel, _) = makeViewModel(payloadStore: store)

        XCTAssertTrue(
            viewModel.clusters.allSatisfy(\.isStale),
            "an hour old is not news, and grey is how this app says so"
        )
    }

    func testAColdStartWithNoNetworkKeepsThePositionsAndSaysSo() async {
        let store = makeStoreFromLastLaunch(sampleVehicles)
        let (viewModel, _) = makeViewModel(
            payloadStore: store,
            error: VehicleAPIError.transport("There is no internet connection.")
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.isOffline)
        XCTAssertEqual(viewModel.clusters.count, 2, "the last known positions stay on the map")
        XCTAssertTrue(viewModel.clusters.allSatisfy(\.isStale))
        XCTAssertEqual(viewModel.lastUpdatedAt, referenceDate.addingTimeInterval(-3_600))
    }

    func testTheFeedNotBeingReachableIsOffline() async {
        let (viewModel, _) = makeViewModel(
            payloadStore: InMemoryVehiclePayloadStore(),
            error: VehicleAPIError.transport("There is no internet connection.")
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.isOffline)
        XCTAssertNotNil(viewModel.errorMessage, "the reason is still there to report")
    }

    func testASuccessfulLoadClearsTheOfflineMark() async {
        let (viewModel, fetcher) = makeViewModel(
            payloadStore: InMemoryVehiclePayloadStore(),
            vehicles: sampleVehicles,
            error: VehicleAPIError.transport("There is no internet connection.")
        )
        await viewModel.load()
        XCTAssertTrue(viewModel.isOffline)

        fetcher.error = nil
        await viewModel.load()

        XCTAssertFalse(viewModel.isOffline)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(
            viewModel.clusters.contains { $0.isStale },
            "a payload that arrives is what makes the map current again"
        )
    }

    func testAFailureToReadTheFeedIsNotOffline() async {
        let (viewModel, _) = makeViewModel(
            payloadStore: InMemoryVehiclePayloadStore(),
            error: VehicleAPIError.malformedPayload("The body was empty.")
        )

        await viewModel.load()

        XCTAssertFalse(viewModel.isOffline, "the feed answered, it just said something unreadable")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testThePayloadIsKeptOnceASession() async {
        let store = InMemoryVehiclePayloadStore()
        let (viewModel, _) = makeViewModel(payloadStore: store, vehicles: sampleVehicles)

        await viewModel.load()
        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(
            store.saves.count,
            1,
            "writing on every refresh would rewrite the file every interval"
        )
        XCTAssertEqual(
            store.saves.first?.fetchedAt,
            referenceDate,
            "kept with the time it was fetched, not the time it was written"
        )
        XCTAssertEqual(store.saves.first?.payload.vehicles.count, 2)
    }

    func testGoingAwayKeepsWhatIsOnScreen() async {
        let store = InMemoryVehiclePayloadStore()
        let (viewModel, _) = makeViewModel(payloadStore: store, vehicles: sampleVehicles)
        await viewModel.load()
        let written = store.saves.count

        viewModel.savePayloadForNextLaunch()

        XCTAssertEqual(store.saves.count, written + 1)
    }

    func testNothingIsKeptWhenNothingWasFetched() {
        let store = InMemoryVehiclePayloadStore()
        let (viewModel, _) = makeViewModel(payloadStore: store)

        viewModel.savePayloadForNextLaunch()

        XCTAssertTrue(store.saves.isEmpty, "there is nothing to keep")
    }
}
