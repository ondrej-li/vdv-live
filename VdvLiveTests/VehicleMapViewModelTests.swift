import CoreLocation
import MapKit
import XCTest
@testable import VdvLive

@MainActor
final class VehicleMapViewModelTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Two vehicles in Jihlava that share a grid cell, one in Havlíčkův Brod
    /// that does not.
    private var sampleVehicles: [Vehicle] {
        [
            Fixture.vehicle(id: 1, latitude: 49.3960, longitude: 15.5910, traction: .bus),
            Fixture.vehicle(id: 2, latitude: 49.3961, longitude: 15.5911, traction: .bus),
            Fixture.vehicle(id: 3, latitude: 49.6070, longitude: 15.5810, traction: .train)
        ]
    }

    /// View model wired to in-memory stores and a detail fetcher that never
    /// touches the network. Automatic refresh starts off so that a test only
    /// sees the fetches it asked for.
    /// `clusterRadiusMetres` is zero unless a test asks for grouping, which is
    /// what the app does too: the tests that are about grouped markers say so.
    private func makeViewModel(
        vehicles: [Vehicle],
        error: Error? = nil,
        detailFetcher: VehicleDetailFetching = StubVehicleDetailFetcher(),
        clusterRadiusMetres: Double = 0
    ) -> (viewModel: VehicleMapViewModel, fetcher: StubVehicleFetcher) {
        let fetcher = StubVehicleFetcher(vehicles: vehicles, error: error)
        let referenceDate = self.referenceDate
        let viewModel = VehicleMapViewModel(
            fetcher: fetcher,
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(
                settings: AppSettings(
                    autoRefreshInterval: AppSettings.defaultAutoRefreshInterval,
                    autoRefreshEnabled: false,
                    language: .czech,
                    clusterRadiusMetres: clusterRadiusMetres
                )
            ),
            languageDefaults: TestDefaults.make(),
            detailFetcher: detailFetcher,
            now: { referenceDate }
        )
        return (viewModel, fetcher)
    }

    /// Same, with the stores handed back so that a test can assert what was
    /// persisted and how often the feed was asked.
    private func makeViewModelWithSettings(
        settings: AppSettings = .default,
        vehicles: [Vehicle] = []
    ) -> (
        viewModel: VehicleMapViewModel,
        fetcher: StubVehicleFetcher,
        settings: InMemoryAppSettingsStore,
        languageDefaults: UserDefaults
    ) {
        let store = InMemoryAppSettingsStore(settings: settings)
        let languageDefaults = TestDefaults.make()
        let fetcher = StubVehicleFetcher(vehicles: vehicles)
        let referenceDate = self.referenceDate
        let viewModel = VehicleMapViewModel(
            fetcher: fetcher,
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: store,
            languageDefaults: languageDefaults,
            detailFetcher: StubVehicleDetailFetcher(),
            now: { referenceDate }
        )
        return (viewModel, fetcher, store, languageDefaults)
    }

    /// Same, with pinned lines already seeded and the store handed back so that
    /// a test can assert what was persisted.
    private func makeViewModelWithFavourites(
        vehicles: [Vehicle],
        pinnedLines: FavouriteLines = FavouriteLines(),
        showsOnlyPinned: Bool = false
    ) -> (viewModel: VehicleMapViewModel, favourites: InMemoryFavouriteLinesStore) {
        let favourites = InMemoryFavouriteLinesStore(
            lines: pinnedLines,
            showsOnlyFavourites: showsOnlyPinned
        )
        let referenceDate = self.referenceDate
        let viewModel = VehicleMapViewModel(
            fetcher: StubVehicleFetcher(vehicles: vehicles),
            favouriteLinesStore: favourites,
            settingsStore: InMemoryAppSettingsStore(
                settings: AppSettings(
                    autoRefreshInterval: AppSettings.defaultAutoRefreshInterval,
                    autoRefreshEnabled: false,
                    language: .czech
                )
            ),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(),
            now: { referenceDate }
        )
        return (viewModel, favourites)
    }

    // MARK: - Loading

    func testStartsEmpty() {
        let (viewModel, _) = makeViewModel(vehicles: sampleVehicles)

        XCTAssertFalse(viewModel.hasLoadedOnce)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertTrue(viewModel.clusters.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadGroupsVehiclesIntoMarkers() async {
        let (viewModel, _) = makeViewModel(vehicles: sampleVehicles, clusterRadiusMetres: 100)

        await viewModel.load()

        XCTAssertEqual(viewModel.vehicleCount, 3)
        XCTAssertEqual(viewModel.visibleVehicleCount, 3)
        XCTAssertEqual(viewModel.clusters.count, 2)
        XCTAssertEqual(viewModel.clusters.map(\.count), [2, 1])
        XCTAssertEqual(viewModel.lastUpdatedAt, referenceDate)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.hasLoadedOnce)
    }

    func testLoadIfNeededOnlyFetchesOnce() async {
        let (viewModel, fetcher) = makeViewModel(vehicles: sampleVehicles)

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        XCTAssertEqual(fetcher.callCount, 1)
    }

    func testReportsAMessageWhenTheFeedCannotBeReached() async {
        // The message the feed layer wrote is passed through as is, in whatever
        // language the app is running in.
        let message = String(localized: "There is no internet connection.")
        let (viewModel, _) = makeViewModel(
            vehicles: [],
            error: VehicleAPIError.transport(message)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.errorMessage, message)
        XCTAssertTrue(viewModel.clusters.isEmpty)
    }

    func testKeepsThePreviousVehiclesWhenARefreshFails() async {
        let (viewModel, fetcher) = makeViewModel(vehicles: sampleVehicles)
        await viewModel.load()

        fetcher.error = VehicleAPIError.httpStatus(503)
        await viewModel.load()

        XCTAssertEqual(viewModel.clusters.count, 3, "a marker per vehicle, none of them dropped")
        XCTAssertEqual(viewModel.vehicleCount, 3)
        XCTAssertEqual(
            viewModel.errorMessage,
            String(format: String(localized: "The map server answered with HTTP %lld."), 503)
        )
    }

    func testClearsTheErrorMessageAfterASuccessfulRetry() async {
        let (viewModel, fetcher) = makeViewModel(
            vehicles: sampleVehicles,
            error: VehicleAPIError.httpStatus(500)
        )
        await viewModel.load()
        XCTAssertNotNil(viewModel.errorMessage)

        fetcher.error = nil
        await viewModel.load()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.clusters.count, 3)
    }

    // MARK: - Filtering

    func testListsTheTractionsPresentInThePayload() async {
        let (viewModel, _) = makeViewModel(vehicles: sampleVehicles)

        await viewModel.load()

        XCTAssertEqual(viewModel.availableTractions, [.bus, .train])
        XCTAssertEqual(viewModel.filter, .all)
    }

    func testFilteringKeepsOnlyTheSelectedTraction() async {
        let (viewModel, _) = makeViewModel(vehicles: sampleVehicles)
        await viewModel.load()

        viewModel.select(filter: .traction(.train))

        XCTAssertEqual(viewModel.vehicleCount, 1)
        XCTAssertEqual(viewModel.clusters.count, 1)
        XCTAssertEqual(viewModel.clusters.first?.representative.traction, .train)

        viewModel.select(filter: .all)

        XCTAssertEqual(viewModel.vehicleCount, 3)
        XCTAssertEqual(viewModel.clusters.count, 3)
    }

    func testKeepsTheFilterWhileAGreyedVehicleIsStillOnTheMap() async {
        let (viewModel, fetcher) = makeViewModel(vehicles: sampleVehicles)
        await viewModel.load()
        viewModel.select(filter: .traction(.train))

        fetcher.payloads = [
            VehiclePayload(
                vehicles: [Fixture.vehicle(id: 4, latitude: 49.3960, longitude: 15.5910, traction: .bus)],
                skippedRecordCount: 0,
                unlocatableRecordCount: 0
            )
        ]
        await viewModel.load()

        // The train is quiet, not gone: it stays on the map greyed out, so the
        // filter the user chose is still worth keeping.
        XCTAssertEqual(viewModel.filter, .traction(.train))
        XCTAssertEqual(viewModel.vehicleCount, 0, "nothing is being reported for that traction")
        XCTAssertEqual(viewModel.clusters.count, 1)
        XCTAssertEqual(viewModel.clusters.first?.isStale, true)
        XCTAssertTrue(viewModel.availableTractions.contains(.train))
    }

    func testDropsTheFilterOnceTheTractionIsReallyGone() async {
        let (viewModel, fetcher) = makeViewModel(vehicles: sampleVehicles)
        await viewModel.load()
        viewModel.select(filter: .traction(.train))

        fetcher.payloads = [
            VehiclePayload(
                vehicles: [Fixture.vehicle(id: 4, latitude: 49.3960, longitude: 15.5910, traction: .bus)],
                skippedRecordCount: 0,
                unlocatableRecordCount: 0
            )
        ]
        // Past the grace, the greyed trains leave and the filter is dropped so
        // that the map is not left empty.
        for _ in 0...VehicleMapViewModel.missingLoadsBeforeRemoval {
            await viewModel.load()
        }

        XCTAssertEqual(viewModel.filter, .all)
        XCTAssertEqual(viewModel.clusters.count, 1)
        XCTAssertEqual(viewModel.vehicleCount, 1)
        XCTAssertFalse(viewModel.availableTractions.contains(.train))
    }

    // MARK: - Pinned lines

    func testStartsWithTheLinesTheStoreHeld() {
        let (viewModel, _) = makeViewModelWithFavourites(
            vehicles: sampleVehicles,
            pinnedLines: FavouriteLines(["420", "337"])
        )

        XCTAssertEqual(viewModel.favouriteLines.orderedForDisplay, ["337", "420"])
    }

    func testPinningSavesToTheStore() {
        let (viewModel, favourites) = makeViewModelWithFavourites(vehicles: sampleVehicles)

        viewModel.toggleFavourite(line: "420")

        XCTAssertTrue(viewModel.isFavourite(line: "420"))
        XCTAssertTrue(favourites.load().contains("420"))
        XCTAssertEqual(favourites.saveCount, 1)

        viewModel.toggleFavourite(line: "420")

        XCTAssertFalse(viewModel.isFavourite(line: "420"))
        XCTAssertTrue(favourites.load().isEmpty)
        XCTAssertEqual(favourites.saveCount, 2)
    }

    func testPinningALineThatIsNotRunningIsKept() async {
        // Line 337 has no vehicles in this payload, which is the case the
        // favourites screen has to support.
        let (viewModel, favourites) = makeViewModelWithFavourites(vehicles: sampleVehicles)
        await viewModel.load()

        viewModel.pin(line: "337")

        XCTAssertTrue(viewModel.isFavourite(line: "337"))
        XCTAssertTrue(favourites.load().contains("337"))
        XCTAssertEqual(viewModel.summary(forLine: "337").vehicleCount, 0)
        XCTAssertFalse(viewModel.summary(forLine: "337").isRunning)
    }

    func testPinnedFilterShowsOnlyVehiclesOnPinnedLines() async {
        let vehicles = [
            Fixture.vehicle(id: 1, line: "420", latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, line: "841334", latitude: 49.6070, longitude: 15.5810),
            Fixture.vehicle(id: 3, line: "420", latitude: 49.2150, longitude: 15.8810)
        ]
        let (viewModel, _) = makeViewModel(vehicles: vehicles)
        await viewModel.load()

        viewModel.pin(line: "420")
        viewModel.select(filter: .favourites)

        XCTAssertEqual(viewModel.vehicleCount, 2)
        XCTAssertEqual(viewModel.clusters.count, 2)
        XCTAssertTrue(viewModel.clusters.allSatisfy { $0.representative.line == "420" })
    }

    func testUnpinningRemovesTheVehiclesFromThePinnedFilter() async {
        let vehicles = [
            Fixture.vehicle(id: 1, line: "420", latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, line: "841334", latitude: 49.6070, longitude: 15.5810)
        ]
        let (viewModel, _) = makeViewModelWithFavourites(vehicles: vehicles, pinnedLines: FavouriteLines(["420"]))
        await viewModel.load()
        viewModel.select(filter: .favourites)
        XCTAssertEqual(viewModel.vehicleCount, 1)

        viewModel.unpin(line: "420")

        XCTAssertEqual(viewModel.vehicleCount, 0)
        XCTAssertTrue(viewModel.clusters.isEmpty)
    }

    func testMarksTheClustersThatHoldAPinnedLine() async {
        let vehicles = [
            Fixture.vehicle(id: 1, line: "420", latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, line: "841334", latitude: 49.3961, longitude: 15.5911),
            Fixture.vehicle(id: 3, line: "5907", latitude: 49.6070, longitude: 15.5810)
        ]
        let (viewModel, _) = makeViewModel(vehicles: vehicles)
        await viewModel.load()
        XCTAssertTrue(viewModel.favouriteClusterIDs.isEmpty)

        viewModel.pin(line: "420")

        // The first cell holds both a pinned and an unpinned vehicle, the
        // second cell holds neither. The marker only needs one of them.
        XCTAssertEqual(viewModel.favouriteClusterIDs.count, 1)
        XCTAssertEqual(viewModel.favouriteClusterIDs, [viewModel.clusters[0].id])

        viewModel.pin(line: "5907")

        XCTAssertEqual(viewModel.favouriteClusterIDs.count, 2)
    }

    func testSummarisesEveryRunningLine() async {
        let vehicles = [
            Fixture.vehicle(id: 1, line: "420", latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, line: "420", latitude: 49.3961, longitude: 15.5911),
            Fixture.vehicle(id: 3, line: "841334", latitude: 49.6070, longitude: 15.5810, traction: .train)
        ]
        let (viewModel, _) = makeViewModel(vehicles: vehicles)

        await viewModel.load()

        XCTAssertEqual(viewModel.runningLines.map(\.line), ["420", "334"])
        XCTAssertEqual(viewModel.runningLines.map(\.vehicleCount), [2, 1])
        XCTAssertEqual(viewModel.runningLines.first?.traction, .bus)
        XCTAssertEqual(viewModel.runningLines.last?.traction, .train)
        XCTAssertEqual(
            viewModel.summary(forLine: "841334").vehicleCountText,
            String(format: String(localized: "%lld vehicles"), 1)
        )
    }

    func testFindsTheFirstVehicleOfALine() async {
        let vehicles = [
            Fixture.vehicle(id: 1, line: "841334", latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, line: "420", latitude: 49.2150, longitude: 15.8810)
        ]
        let (viewModel, _) = makeViewModel(vehicles: vehicles)
        await viewModel.load()

        XCTAssertEqual(viewModel.firstVehicle(forLine: "420")?.id, 2)
        XCTAssertEqual(viewModel.firstVehicle(forLine: " 420 ")?.id, 2)
        XCTAssertNil(viewModel.firstVehicle(forLine: "337"))
    }

    func testFilterChipsAlwaysOfferThePinnedLines() async {
        let (viewModel, _) = makeViewModel(vehicles: sampleVehicles)

        await viewModel.load()

        XCTAssertEqual(viewModel.availableFilters, [.all, .favourites, .traction(.bus), .traction(.train)])
    }

    // MARK: - Showing pinned lines only

    func testStartsShowingEverythingWhenNothingWasChosenBefore() {
        let (viewModel, _) = makeViewModel(vehicles: sampleVehicles)

        XCTAssertEqual(viewModel.filter, .all)
        XCTAssertFalse(viewModel.showsOnlyPinnedLines)
    }

    func testStartsShowingOnlyPinnedLinesWhenThatWasLeftOn() async {
        let (viewModel, _) = makeViewModelWithFavourites(
            vehicles: sampleVehicles,
            pinnedLines: FavouriteLines(["841334"]),
            showsOnlyPinned: true
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.filter, .favourites)
        XCTAssertTrue(viewModel.showsOnlyPinnedLines)
        XCTAssertEqual(viewModel.vehicleCount, 3)
        XCTAssertTrue(viewModel.clusters.allSatisfy { $0.representative.line == "841334" })
    }

    func testChoosingThePinnedFilterIsRememberedForTheNextLaunch() {
        let (viewModel, favourites) = makeViewModelWithFavourites(vehicles: sampleVehicles)

        viewModel.select(filter: .favourites)
        XCTAssertTrue(favourites.loadShowsOnlyFavourites())

        viewModel.select(filter: .all)
        XCTAssertFalse(favourites.loadShowsOnlyFavourites())
    }

    func testChoosingATractionFilterTurnsThePinnedOnlyModeOff() {
        let (viewModel, favourites) = makeViewModelWithFavourites(
            vehicles: sampleVehicles,
            showsOnlyPinned: true
        )

        viewModel.select(filter: .traction(.bus))

        XCTAssertFalse(viewModel.showsOnlyPinnedLines)
        XCTAssertFalse(favourites.loadShowsOnlyFavourites())
    }

    func testTogglingPinnedOnlyFromTheSheetNarrowsAndRestoresTheMap() async {
        let vehicles = [
            Fixture.vehicle(id: 1, line: "420", latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, line: "841334", latitude: 49.6070, longitude: 15.5810)
        ]
        let (viewModel, _) = makeViewModelWithFavourites(
            vehicles: vehicles,
            pinnedLines: FavouriteLines(["420"])
        )
        await viewModel.load()
        XCTAssertEqual(viewModel.vehicleCount, 2)

        viewModel.setShowsOnlyPinnedLines(true)

        XCTAssertEqual(viewModel.vehicleCount, 1)
        XCTAssertEqual(viewModel.clusters.count, 1)
        XCTAssertEqual(viewModel.clusters.first?.representative.line, "420")

        viewModel.setShowsOnlyPinnedLines(false)

        XCTAssertEqual(viewModel.vehicleCount, 2)
    }

    func testOffersTheFirstPinnedLineThatIsRunningToJumpTo() async {
        let vehicles = [
            Fixture.vehicle(id: 1, line: "420", latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, line: "841334", latitude: 49.6070, longitude: 15.5810)
        ]
        // 337 sorts first but has no vehicles, so 420 is the one worth offering.
        let (viewModel, _) = makeViewModelWithFavourites(
            vehicles: vehicles,
            pinnedLines: FavouriteLines(["337", "420"])
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.firstRunningPinnedLine, "420")
    }

    func testOffersNoJumpWhenNoPinnedLineIsRunning() async {
        let (viewModel, _) = makeViewModelWithFavourites(
            vehicles: [Fixture.vehicle(id: 1, line: "841334")],
            pinnedLines: FavouriteLines(["337"])
        )

        await viewModel.load()

        XCTAssertNil(viewModel.firstRunningPinnedLine)
    }

    // MARK: - Line codes and runs

    func testPinningByLineNumberFindsTheOperatorPrefixedCode() async {
        let vehicles = [
            Fixture.vehicle(id: 1, line: "764337", latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, line: "764420", latitude: 49.6070, longitude: 15.5810)
        ]
        let (viewModel, _) = makeViewModel(vehicles: vehicles)
        await viewModel.load()

        viewModel.pin(line: "337")
        viewModel.select(filter: .favourites)

        XCTAssertEqual(viewModel.vehicleCount, 1)
        XCTAssertEqual(viewModel.clusters.first?.representative.line, "764337")
    }

    func testPinningAPrefixedCodeFilesItUnderTheLineNumber() async {
        let (viewModel, _) = makeViewModel(vehicles: sampleVehicles)

        viewModel.pin(line: "764337")

        XCTAssertEqual(viewModel.favouriteLines.orderedForDisplay, ["337"])
        XCTAssertTrue(viewModel.isFavourite(line: "337"))
        XCTAssertTrue(viewModel.isFavourite(line: "764337"))
    }

    func testGroupsRunningLinesByThePassengerFacingNumber() async {
        let vehicles = [
            Fixture.vehicle(id: 1, line: "764337", latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, line: "841337", latitude: 49.6070, longitude: 15.5810),
            Fixture.vehicle(id: 3, line: "764420", latitude: 49.2150, longitude: 15.8810)
        ]
        let (viewModel, _) = makeViewModel(vehicles: vehicles)

        await viewModel.load()

        XCTAssertEqual(viewModel.runningLines.map(\.line), ["337", "420"])
        XCTAssertEqual(viewModel.runningLines.first?.vehicleCount, 2)
        XCTAssertEqual(viewModel.runningLines.first?.operatorCode, "764")
        XCTAssertEqual(viewModel.runningLines.last?.operatorCode, "764")
        XCTAssertEqual(
            viewModel.runningLines.first?.descriptionText,
            String(
                format: String(localized: "%@ · operator %@"),
                String(localized: "Bus"),
                "764"
            )
        )
    }

    func testFindsAVehicleOfAPinnedLineNumber() async {
        let vehicles = [Fixture.vehicle(id: 7, line: "764337")]
        let (viewModel, _) = makeViewModel(vehicles: vehicles)
        await viewModel.load()

        XCTAssertEqual(viewModel.firstVehicle(forLine: "337")?.id, 7)
    }

    // MARK: - Vehicle detail

    func testLoadsTheDetailOfASingleVehicleMarker() async {
        let vehicles = [Fixture.vehicle(id: 42, line: "764337", latitude: 49.3960, longitude: 15.5910)]
        let detailFetcher = StubVehicleDetailFetcher()
        let (viewModel, _) = makeViewModel(vehicles: vehicles, detailFetcher: detailFetcher)
        await viewModel.load()

        viewModel.selectedClusterID = viewModel.clusters.first?.id
        await viewModel.selectionDidChange()

        XCTAssertEqual(detailFetcher.requestedVehicleIDs, [42])
        XCTAssertEqual(viewModel.vehicleDetail?.stopName, "Stop 42")
        XCTAssertFalse(viewModel.isLoadingDetail)
    }

    func testDoesNotFetchDetailForAMergedMarker() async {
        let vehicles = [
            Fixture.vehicle(id: 1, line: "764337", latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, line: "764338", latitude: 49.3961, longitude: 15.5911)
        ]
        let detailFetcher = StubVehicleDetailFetcher()
        let (viewModel, _) = makeViewModel(
            vehicles: vehicles,
            detailFetcher: detailFetcher,
            clusterRadiusMetres: 100
        )
        await viewModel.load()

        viewModel.selectedClusterID = viewModel.clusters.first?.id
        await viewModel.selectionDidChange()

        XCTAssertTrue(detailFetcher.requestedVehicleIDs.isEmpty)
        XCTAssertNil(viewModel.vehicleDetail)
    }

    func testClearsTheDetailWhenTheSelectionGoesAway() async {
        let vehicles = [Fixture.vehicle(id: 42, latitude: 49.3960, longitude: 15.5910)]
        let (viewModel, _) = makeViewModel(vehicles: vehicles)
        await viewModel.load()
        viewModel.selectedClusterID = viewModel.clusters.first?.id
        await viewModel.selectionDidChange()
        XCTAssertNotNil(viewModel.vehicleDetail)

        viewModel.selectedClusterID = nil
        await viewModel.selectionDidChange()

        XCTAssertNil(viewModel.vehicleDetail)
        XCTAssertFalse(viewModel.isLoadingDetail)
    }

    func testClearsTheDetailWhenTheSelectedMarkerLeavesTheScreen() async {
        let vehicles = [Fixture.vehicle(id: 42, latitude: 49.3960, longitude: 15.5910)]
        let (viewModel, _) = makeViewModel(vehicles: vehicles)
        await viewModel.load()
        viewModel.selectedClusterID = viewModel.clusters.first?.id
        await viewModel.selectionDidChange()
        XCTAssertNotNil(viewModel.vehicleDetail)

        viewModel.updateVisibleRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 49.9, longitude: 16.5),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        )

        XCTAssertNil(viewModel.vehicleDetail)
        XCTAssertNil(viewModel.selectedClusterID)
    }

    func testKeepsTheNewestDetailWhenTwoVehiclesAreSelectedInARow() async {
        let vehicles = [
            Fixture.vehicle(id: 1, latitude: 49.3960, longitude: 15.5910),
            Fixture.vehicle(id: 2, latitude: 49.6070, longitude: 15.5810)
        ]
        let detailFetcher = StubVehicleDetailFetcher(delay: .milliseconds(30))
        let (viewModel, _) = makeViewModel(vehicles: vehicles, detailFetcher: detailFetcher)
        await viewModel.load()

        // The first lookup is started, but a second selection follows before it
        // can answer. The late answer of the first one must not overwrite the
        // card that belongs to the second.
        let firstLookup = Task { await viewModel.loadDetail(for: vehicles[0]) }
        try? await Task.sleep(for: .milliseconds(5))
        await viewModel.loadDetail(for: vehicles[1])
        await firstLookup.value

        XCTAssertEqual(viewModel.vehicleDetail?.stopName, "Stop 2")
        XCTAssertFalse(viewModel.isLoadingDetail)
    }

    func testDetailFailureLeavesTheCardWithoutTheExtraRows() async {
        let vehicles = [Fixture.vehicle(id: 42, latitude: 49.3960, longitude: 15.5910)]
        let detailFetcher = StubVehicleDetailFetcher(error: VehicleAPIError.httpStatus(500))
        let (viewModel, _) = makeViewModel(vehicles: vehicles, detailFetcher: detailFetcher)
        await viewModel.load()

        viewModel.selectedClusterID = viewModel.clusters.first?.id
        await viewModel.selectionDidChange()

        XCTAssertNil(viewModel.vehicleDetail)
        XCTAssertFalse(viewModel.isLoadingDetail)
        XCTAssertEqual(viewModel.clusters.count, 1)
    }

    // MARK: - Visible region

    func testZoomingInDropsVehiclesThatAreOffScreen() async {
        let (viewModel, _) = makeViewModel(vehicles: sampleVehicles, clusterRadiusMetres: 100)
        await viewModel.load()
        XCTAssertEqual(viewModel.clusters.count, 2)
        XCTAssertEqual(viewModel.visibleVehicleCount, 3)

        // Deliberately not centred on the vehicles: the two that stay on screen
        // have to be inside whatever box the view model derives.
        viewModel.updateVisibleRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 49.3950, longitude: 15.5900),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )

        XCTAssertEqual(viewModel.vehicleCount, 3)
        XCTAssertEqual(viewModel.visibleVehicleCount, 2)
        XCTAssertEqual(viewModel.clusters.count, 1)
        XCTAssertEqual(viewModel.clusters.first?.count, 2)
    }

    func testRepeatedUpdatesForTheSameRegionAreIgnored() async {
        let (viewModel, _) = makeViewModel(vehicles: sampleVehicles)
        await viewModel.load()

        let region = RegionOfInterest.vysocina.region
        viewModel.updateVisibleRegion(region)
        let clusters = viewModel.clusters
        viewModel.updateVisibleRegion(region)

        XCTAssertEqual(viewModel.clusters, clusters)
    }

    // MARK: - Selection

    func testResolvesTheSelectedMarkerAndForgetsItWhenItLeavesTheScreen() async {
        let (viewModel, _) = makeViewModel(vehicles: sampleVehicles)
        await viewModel.load()
        let selectedID = viewModel.clusters.first?.id

        viewModel.selectedClusterID = selectedID

        XCTAssertEqual(viewModel.selectedCluster?.representative.id, 1)

        viewModel.updateVisibleRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 49.9, longitude: 16.5),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        )

        XCTAssertNil(viewModel.selectedClusterID)
        XCTAssertNil(viewModel.selectedCluster)
    }

    // MARK: - Automatic refresh

    func testAutomaticRefreshKeepsFetchingUntilItIsStopped() async throws {
        // The interval comes straight from the store here: the public setter
        // clamps to the five second minimum, which no test should have to wait
        // for.
        let (viewModel, fetcher, _, _) = makeViewModelWithSettings(
            settings: AppSettings(
                autoRefreshInterval: 0.05,
                autoRefreshEnabled: true,
                language: .czech
            ),
            vehicles: sampleVehicles
        )
        XCTAssertTrue(viewModel.isAutoRefreshEnabled)

        try await Task.sleep(nanoseconds: 300_000_000)
        viewModel.stopAutoRefresh()
        // Let a fetch that was already in flight finish before counting, or the
        // count moves on its own and the comparison below means nothing.
        try await Task.sleep(nanoseconds: 200_000_000)
        let callsAfterStop = fetcher.callCount

        XCTAssertGreaterThan(callsAfterStop, 1)
        XCTAssertFalse(viewModel.isAutoRefreshEnabled)

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(fetcher.callCount, callsAfterStop)
    }

    func testDefaultSettingsRefreshEveryFifteenSeconds() {
        let (viewModel, _, store, _) = makeViewModelWithSettings()

        XCTAssertTrue(viewModel.isAutoRefreshEnabled)
        XCTAssertEqual(viewModel.autoRefreshInterval, 15)
        XCTAssertEqual(viewModel.settings.language, .czech)
        XCTAssertEqual(store.load(), .default)
    }

    func testRefreshIntervalIsClampedToTheMinimumAndPersisted() {
        let (viewModel, _, store, _) = makeViewModelWithSettings()

        viewModel.setAutoRefreshInterval(1)

        XCTAssertEqual(viewModel.autoRefreshInterval, AppSettings.minimumAutoRefreshInterval)
        XCTAssertEqual(store.load().autoRefreshInterval, AppSettings.minimumAutoRefreshInterval)
        XCTAssertEqual(store.saveCount, 1)

        viewModel.setAutoRefreshInterval(120)

        XCTAssertEqual(viewModel.autoRefreshInterval, 120)
        XCTAssertEqual(store.load().autoRefreshInterval, 120)
    }

    func testTurningAutomaticRefreshOffKeepsTheChosenInterval() {
        let (viewModel, fetcher, store, _) = makeViewModelWithSettings(
            settings: AppSettings(
                autoRefreshInterval: 60,
                autoRefreshEnabled: false,
                language: .czech
            ),
            vehicles: sampleVehicles
        )

        viewModel.setAutoRefresh(enabled: true)
        XCTAssertTrue(viewModel.isAutoRefreshEnabled)
        XCTAssertEqual(viewModel.autoRefreshInterval, 60)

        viewModel.setAutoRefresh(enabled: false)
        XCTAssertFalse(viewModel.isAutoRefreshEnabled)
        XCTAssertEqual(viewModel.autoRefreshInterval, 60)
        XCTAssertEqual(store.load().autoRefreshInterval, 60)
        XCTAssertEqual(fetcher.callCount, 0)
    }

    func testLanguageChangeIsPersistedAndWrittenForTheNextLaunch() {
        let (viewModel, _, store, languageDefaults) = makeViewModelWithSettings()
        let deviceLanguages = TestDefaults.deviceLanguages(in: languageDefaults)

        viewModel.setLanguage(.english)

        XCTAssertEqual(viewModel.settings.language, .english)
        XCTAssertEqual(store.load().language, .english)
        XCTAssertEqual(languageDefaults.array(forKey: LanguageOverride.defaultsKey) as? [String], ["en"])

        viewModel.setLanguage(.system)

        XCTAssertEqual(store.load().language, .system)
        XCTAssertEqual(
            languageDefaults.array(forKey: LanguageOverride.defaultsKey) as? [String],
            deviceLanguages
        )
    }

    // MARK: - Marker motion

    func testMarkersGlideToTheirNewPosition() async throws {
        let parked = Fixture.vehicle(id: 1, latitude: 49.3960, longitude: 15.5910)
        let moved = Fixture.vehicle(id: 1, latitude: 49.3980, longitude: 15.5930)
        let fetcher = StubVehicleFetcher(payloads: [
            VehiclePayload(vehicles: [parked], skippedRecordCount: 0, unlocatableRecordCount: 0),
            VehiclePayload(vehicles: [moved], skippedRecordCount: 0, unlocatableRecordCount: 0)
        ])
        let referenceDate = self.referenceDate
        let viewModel = VehicleMapViewModel(
            fetcher: fetcher,
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(),
            markerMotionDuration: 0.4,
            now: { referenceDate }
        )

        await viewModel.load()
        let firstID = try XCTUnwrap(viewModel.clusters.first).id
        XCTAssertEqual(
            try XCTUnwrap(viewModel.clusters.first).drawnCoordinate.latitude,
            49.3960,
            accuracy: 0.000001
        )

        await viewModel.load()
        let secondID = try XCTUnwrap(viewModel.clusters.first).id
        XCTAssertEqual(firstID, secondID, "both positions have to fall in the same grid cell")

        // Straight after the payload the marker is still where it was drawn, not
        // where the feed just put it.
        let beforeMoving = try XCTUnwrap(viewModel.clusters.first).drawnCoordinate
        XCTAssertGreaterThanOrEqual(beforeMoving.latitude, 49.3960)
        XCTAssertLessThan(beforeMoving.latitude, 49.3980)

        try await Task.sleep(for: .milliseconds(120))

        let halfWay = try XCTUnwrap(viewModel.clusters.first).drawnCoordinate
        XCTAssertGreaterThan(halfWay.latitude, 49.3960)
        XCTAssertLessThan(halfWay.latitude, 49.3980)

        try await Task.sleep(for: .milliseconds(700))

        let arrived = try XCTUnwrap(viewModel.clusters.first).drawnCoordinate
        XCTAssertEqual(arrived.latitude, 49.3980, accuracy: 0.000001)
        XCTAssertEqual(arrived.longitude, 15.5930, accuracy: 0.000001)
        XCTAssertEqual(viewModel.clusters.first?.coordinate.latitude ?? 0, 49.3980, accuracy: 0.000001)
    }

    func testANewMarkerAppearsWhereItIs() async throws {
        let parked = Fixture.vehicle(id: 1, latitude: 49.3960, longitude: 15.5910)
        let appeared = Fixture.vehicle(id: 2, latitude: 49.6070, longitude: 15.5810)
        let fetcher = StubVehicleFetcher(payloads: [
            VehiclePayload(vehicles: [parked], skippedRecordCount: 0, unlocatableRecordCount: 0),
            VehiclePayload(
                vehicles: [parked, appeared],
                skippedRecordCount: 0,
                unlocatableRecordCount: 0
            )
        ])
        let referenceDate = self.referenceDate
        let viewModel = VehicleMapViewModel(
            fetcher: fetcher,
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(),
            markerMotionDuration: 5,
            now: { referenceDate }
        )

        await viewModel.load()
        await viewModel.load()

        // Nothing to travel from, so a marker that just appeared is simply
        // there, however long the glide for the others would have been.
        let cluster = try XCTUnwrap(viewModel.clusters.first { $0.singleVehicle?.id == 2 })
        XCTAssertEqual(cluster.drawnCoordinate.latitude, 49.6070, accuracy: 0.000001)
        XCTAssertEqual(cluster.drawnCoordinate.longitude, 15.5810, accuracy: 0.000001)
    }
}

/// Scratch user defaults for a single test.
///
/// The language override goes through `UserDefaults`; the app the tests run
/// inside must not have its own language changed by them.
enum TestDefaults {
    static func make() -> UserDefaults {
        let name = "VdvLiveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Languages the device itself asks for, before the app wrote an override.
    static func deviceLanguages(in defaults: UserDefaults) -> [String] {
        defaults.array(forKey: LanguageOverride.defaultsKey) as? [String] ?? []
    }
}
