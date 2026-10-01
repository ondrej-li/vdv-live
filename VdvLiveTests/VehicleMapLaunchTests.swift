import CoreLocation
import MapKit
import XCTest
@testable import VdvLive

/// Which viewport the map opens on, and what the lock button remembers.
@MainActor
final class VehicleMapLaunchTests: XCTestCase {
    private let jihlava = CLLocationCoordinate2D(latitude: 49.3960, longitude: 15.5910)
    private let prague = CLLocationCoordinate2D(latitude: 50.0875, longitude: 14.4213)

    /// Stands in for "whatever the user was looking at" when the lock is pressed.
    private var pelhrimovView: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 49.4310, longitude: 15.2230),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.08)
        )
    }

    private var regionCenter: CLLocationCoordinate2D {
        RegionOfInterest.vysocina.region.center
    }

    private func makeViewModel(
        settings: AppSettings,
        coordinate: CLLocationCoordinate2D? = nil
    ) -> (
        viewModel: VehicleMapViewModel,
        store: InMemoryAppSettingsStore,
        location: StubLocationProvider
    ) {
        let store = InMemoryAppSettingsStore(settings: settings)
        let location = StubLocationProvider(coordinate: coordinate)
        let viewModel = VehicleMapViewModel(
            fetcher: StubVehicleFetcher(),
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: store,
            locationProvider: location,
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher()
        )
        return (viewModel, store, location)
    }

    private func settings(
        startsAtCurrentLocation: Bool = true,
        savedMapView: SavedMapView? = nil,
        showsCurrentLocation: Bool = true,
        followsCurrentLocation: Bool = false
    ) -> AppSettings {
        AppSettings(
            autoRefreshInterval: AppSettings.defaultAutoRefreshInterval,
            autoRefreshEnabled: false,
            language: .czech,
            startsAtCurrentLocation: startsAtCurrentLocation,
            savedMapView: savedMapView,
            showsCurrentLocation: showsCurrentLocation,
            followsCurrentLocation: followsCurrentLocation
        )
    }

    // MARK: - Opening at the current location

    func testTheMapStartsAtTheCurrentLocationByDefault() {
        let (viewModel, _, _) = makeViewModel(settings: .default)

        XCTAssertTrue(viewModel.startsAtCurrentLocation)
        XCTAssertNil(viewModel.savedMapView)
    }

    func testTheMapOpensTenKilometresAroundTheUser() async throws {
        let (viewModel, _, location) = makeViewModel(settings: settings(), coordinate: jihlava)

        let located = await viewModel.currentLocationRegion()
        let region = try XCTUnwrap(located)

        XCTAssertEqual(region.center.latitude, 49.3960, accuracy: 1e-9)
        XCTAssertEqual(region.center.longitude, 15.5910, accuracy: 1e-9)
        XCTAssertEqual(region.span.latitudeDelta, 0.09, accuracy: 0.001)
        XCTAssertEqual(location.requestCount, 1)
    }

    func testWithoutAPositionTheMapOpensOnTheWholeRegion() async {
        let (viewModel, _, _) = makeViewModel(settings: settings(), coordinate: nil)

        let region = await viewModel.currentLocationRegion()

        XCTAssertNil(region)
        XCTAssertEqual(viewModel.launchRegion.center.latitude, regionCenter.latitude, accuracy: 1e-9)
        XCTAssertEqual(viewModel.launchRegion.center.longitude, regionCenter.longitude, accuracy: 1e-9)
    }

    func testAPositionOutsideTheRegionIsIgnored() async {
        // Opening a map of Prague would show an empty map: the feed only covers
        // one region, so the usual view is the better answer.
        let (viewModel, _, _) = makeViewModel(settings: settings(), coordinate: prague)

        let region = await viewModel.currentLocationRegion()

        XCTAssertNil(region)
    }

    func testTurningTheOptionOffLeavesTheMapOnTheRegion() async {
        let (viewModel, _, location) = makeViewModel(
            settings: settings(startsAtCurrentLocation: false),
            coordinate: jihlava
        )

        let region = await viewModel.currentLocationRegion()

        XCTAssertNil(region)
        XCTAssertEqual(location.requestCount, 0, "a switched off option should not ask for a position")
    }

    // MARK: - Showing the position

    func testThePositionIsShownByDefault() {
        let (viewModel, _, _) = makeViewModel(settings: .default)

        XCTAssertTrue(AppSettings.default.showsCurrentLocation)
        XCTAssertTrue(viewModel.showsCurrentLocation)
    }

    func testTurningThePositionOffIsPersisted() {
        let (viewModel, store, _) = makeViewModel(settings: settings())

        viewModel.setShowsCurrentLocation(false)

        XCTAssertFalse(viewModel.showsCurrentLocation)
        XCTAssertFalse(store.load().showsCurrentLocation)
        XCTAssertEqual(store.saveCount, 1)

        viewModel.setShowsCurrentLocation(false)

        XCTAssertEqual(store.saveCount, 1, "the same value twice is not a change")
    }

    func testPermissionIsAskedForWhenThePositionIsShown() async {
        let (viewModel, _, location) = makeViewModel(settings: settings(showsCurrentLocation: true))

        await viewModel.requestLocationPermissionIfNeeded()

        XCTAssertEqual(location.authorizationRequestCount, 1)
    }

    func testNoPermissionIsAskedForWhenThePositionIsHidden() async {
        let (viewModel, _, location) = makeViewModel(settings: settings(showsCurrentLocation: false))

        await viewModel.requestLocationPermissionIfNeeded()

        XCTAssertEqual(location.authorizationRequestCount, 0)
    }

    // MARK: - Following the position

    func testFollowingIsOffByDefault() {
        let (viewModel, _, _) = makeViewModel(settings: .default)

        XCTAssertFalse(AppSettings.default.followsCurrentLocation)
        XCTAssertFalse(viewModel.followsCurrentLocation)
    }

    func testTurningFollowingOnIsPersisted() {
        let (viewModel, store, _) = makeViewModel(settings: settings())

        viewModel.setFollowsCurrentLocation(true)

        XCTAssertTrue(viewModel.followsCurrentLocation)
        XCTAssertTrue(store.load().followsCurrentLocation)
        XCTAssertEqual(store.saveCount, 1)

        viewModel.setFollowsCurrentLocation(true)

        XCTAssertEqual(store.saveCount, 1, "the same value twice is not a change")
    }

    func testStoppingFollowingIsPersisted() {
        let (viewModel, store, _) = makeViewModel(settings: settings(followsCurrentLocation: true))
        XCTAssertTrue(viewModel.followsCurrentLocation)

        // What a pan, the recenter button and flying to a vehicle all do.
        viewModel.setFollowsCurrentLocation(false)

        XCTAssertFalse(viewModel.followsCurrentLocation)
        XCTAssertFalse(store.load().followsCurrentLocation)
    }

    func testPermissionIsAskedForWhenFollowingEvenWithoutTheDot() async {
        let (viewModel, _, location) = makeViewModel(
            settings: settings(showsCurrentLocation: false, followsCurrentLocation: true)
        )

        await viewModel.requestLocationPermissionIfNeeded()

        XCTAssertEqual(location.authorizationRequestCount, 1)
    }

    // MARK: - The locked viewport

    func testALockedViewportOutranksTheCurrentLocation() async throws {
        let saved = try XCTUnwrap(SavedMapView(region: pelhrimovView))
        let (viewModel, _, location) = makeViewModel(
            settings: settings(savedMapView: saved),
            coordinate: jihlava
        )

        let region = await viewModel.currentLocationRegion()

        XCTAssertNil(region)
        XCTAssertEqual(location.requestCount, 0, "a locked viewport is a decision, not a hint")
        XCTAssertEqual(viewModel.launchRegion.center.latitude, 49.4310, accuracy: 1e-6)
        XCTAssertEqual(viewModel.launchRegion.center.longitude, 15.2230, accuracy: 1e-6)
        XCTAssertEqual(viewModel.launchRegion.span.latitudeDelta, 0.05, accuracy: 1e-9)
        XCTAssertEqual(viewModel.launchRegion.span.longitudeDelta, 0.08, accuracy: 1e-9)
    }

    func testTheLockButtonSavesTheViewportOnScreen() throws {
        let (viewModel, store, _) = makeViewModel(settings: settings())
        viewModel.updateVisibleRegion(pelhrimovView)

        viewModel.toggleSavedMapView()

        let saved = try XCTUnwrap(viewModel.savedMapView)
        XCTAssertEqual(saved.latitude, 49.4310, accuracy: 1e-6)
        XCTAssertEqual(saved.longitude, 15.2230, accuracy: 1e-6)
        XCTAssertEqual(saved.latitudeDelta, 0.05, accuracy: 1e-9)
        XCTAssertEqual(saved.longitudeDelta, 0.08, accuracy: 1e-9)
        XCTAssertEqual(store.load().savedMapView, saved)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(viewModel.launchRegion.center.latitude, 49.4310, accuracy: 1e-6)
    }

    func testPressingTheLockAgainForgetsTheViewport() {
        let (viewModel, store, _) = makeViewModel(settings: settings())
        viewModel.updateVisibleRegion(pelhrimovView)
        viewModel.toggleSavedMapView()

        viewModel.toggleSavedMapView()

        XCTAssertNil(viewModel.savedMapView)
        XCTAssertNil(store.load().savedMapView)
        XCTAssertEqual(viewModel.launchRegion.center.latitude, regionCenter.latitude, accuracy: 1e-9)
        XCTAssertEqual(viewModel.launchRegion.center.longitude, regionCenter.longitude, accuracy: 1e-9)
    }

    func testAViewportThatCannotBeRestoredIsNotSaved() {
        let (viewModel, store, _) = makeViewModel(settings: settings())
        viewModel.updateVisibleRegion(
            MKCoordinateRegion(
                center: jihlava,
                span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)
            )
        )

        viewModel.toggleSavedMapView()

        XCTAssertNil(viewModel.savedMapView)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testTheSavedViewportCanBeClearedFromTheSettings() {
        let (viewModel, store, _) = makeViewModel(settings: settings())
        viewModel.updateVisibleRegion(pelhrimovView)
        viewModel.toggleSavedMapView()

        viewModel.setSavedMapView(nil)

        XCTAssertNil(viewModel.savedMapView)
        XCTAssertNil(store.load().savedMapView)
    }

    // MARK: - The setting itself

    func testTurningTheOptionOffIsPersistedOnce() {
        let (viewModel, store, _) = makeViewModel(settings: settings())

        viewModel.setStartsAtCurrentLocation(false)

        XCTAssertFalse(viewModel.startsAtCurrentLocation)
        XCTAssertFalse(store.load().startsAtCurrentLocation)
        XCTAssertEqual(store.saveCount, 1)

        viewModel.setStartsAtCurrentLocation(false)

        XCTAssertEqual(store.saveCount, 1, "the same value twice is not a change")
    }
}
