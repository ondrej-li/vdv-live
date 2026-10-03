import CoreLocation
import MapKit
import XCTest
@testable import VdvLive

@MainActor
final class AppSettingsTests: XCTestCase {
    // MARK: - Defaults and clamping

    func testDefaultSettingsAreCzechWithFifteenSecondRefresh() {
        XCTAssertEqual(AppSettings.default.autoRefreshInterval, 15)
        XCTAssertTrue(AppSettings.default.autoRefreshEnabled)
        XCTAssertEqual(AppSettings.default.language, .czech)
    }

    func testIntervalIsClampedToTheMinimum() {
        XCTAssertEqual(
            AppSettings.clampedAutoRefreshInterval(1),
            AppSettings.minimumAutoRefreshInterval
        )
        XCTAssertEqual(
            AppSettings.clampedAutoRefreshInterval(0),
            AppSettings.minimumAutoRefreshInterval
        )
        XCTAssertEqual(
            AppSettings.clampedAutoRefreshInterval(-30),
            AppSettings.minimumAutoRefreshInterval
        )
        XCTAssertEqual(AppSettings.clampedAutoRefreshInterval(120), 120)
        XCTAssertEqual(
            AppSettings.clampedAutoRefreshInterval(.infinity),
            AppSettings.defaultAutoRefreshInterval
        )
    }

    func testEveryOfferedIntervalIsAboveTheMinimum() {
        XCTAssertTrue(
            AppSettings.selectableAutoRefreshIntervals.allSatisfy {
                $0 >= AppSettings.minimumAutoRefreshInterval
            }
        )
        XCTAssertTrue(
            AppSettings.selectableAutoRefreshIntervals.contains(AppSettings.defaultAutoRefreshInterval)
        )
    }

    func testValidatedSettingsApplyTheMinimum() {
        let settings = AppSettings.validated(
            AppSettings(autoRefreshInterval: 2, autoRefreshEnabled: true, language: .english)
        )

        XCTAssertEqual(settings.autoRefreshInterval, AppSettings.minimumAutoRefreshInterval)
        XCTAssertEqual(settings.language, .english)
    }

    // MARK: - Store

    func testStoreRoundTripsTheSettings() {
        let store = UserDefaultsAppSettingsStore(defaults: TestDefaults.make())

        XCTAssertEqual(store.load(), .default)

        let changed = AppSettings(
            autoRefreshInterval: 60,
            autoRefreshEnabled: false,
            language: .english
        )
        store.save(changed)

        XCTAssertEqual(store.load(), changed)
    }

    /// The stops are matched from OpenStreetMap rather than published with the
    /// timetables, so they cover most of the region and not all of it. A map that
    /// drew them without being asked would be claiming more than it has.
    func testStopsAreNotDrawnUntilTheyAreAskedFor() {
        XCTAssertFalse(AppSettings.default.showsStops)
    }

    func testStoreRoundTripsTheStopFlagsChoice() {
        let store = UserDefaultsAppSettingsStore(defaults: TestDefaults.make())
        var settings = store.load()
        XCTAssertFalse(settings.showsStops)

        settings.showsStops = true
        store.save(settings)

        XCTAssertTrue(store.load().showsStops)
    }

    func testStoreClampsAStoredIntervalBelowTheMinimum() {
        let defaults = TestDefaults.make()
        defaults.set(1.0, forKey: UserDefaultsAppSettingsStore.autoRefreshIntervalKey)

        let settings = UserDefaultsAppSettingsStore(defaults: defaults).load()

        XCTAssertEqual(settings.autoRefreshInterval, AppSettings.minimumAutoRefreshInterval)
    }

    func testStoreFallsBackToCzechForAnUnknownLanguage() {
        let defaults = TestDefaults.make()
        defaults.set("klingon", forKey: UserDefaultsAppSettingsStore.languageKey)

        let settings = UserDefaultsAppSettingsStore(defaults: defaults).load()

        XCTAssertEqual(settings.language, .czech)
    }

    func testInMemoryStoreKeepsWhatItIsGiven() {
        let store = InMemoryAppSettingsStore(
            settings: AppSettings(autoRefreshInterval: 0.05, autoRefreshEnabled: false, language: .system)
        )

        XCTAssertEqual(store.load().autoRefreshInterval, 0.05)
        XCTAssertFalse(store.load().autoRefreshEnabled)

        store.save(.default)

        XCTAssertEqual(store.load(), .default)
        XCTAssertEqual(store.saveCount, 1)
    }

    // MARK: - Where the map opens

    func testTheMapStartsAtTheCurrentLocationByDefault() {
        XCTAssertTrue(AppSettings.default.startsAtCurrentLocation)
        XCTAssertNil(AppSettings.default.savedMapView)
    }

    func testStoreRoundTripsTheSavedViewport() throws {
        let store = UserDefaultsAppSettingsStore(defaults: TestDefaults.make())
        var settings = AppSettings.default
        settings.savedMapView = try XCTUnwrap(
            SavedMapView(
                region: MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 49.3960, longitude: 15.5910),
                    span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.138)
                )
            )
        )
        settings.startsAtCurrentLocation = false

        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded.savedMapView, settings.savedMapView)
        XCTAssertFalse(loaded.startsAtCurrentLocation)
    }

    func testStoreForgetsTheViewportWhenItIsCleared() throws {
        let store = UserDefaultsAppSettingsStore(defaults: TestDefaults.make())
        var settings = AppSettings.default
        settings.savedMapView = try XCTUnwrap(
            SavedMapView(
                region: MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 49.3960, longitude: 15.5910),
                    span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.138)
                )
            )
        )
        store.save(settings)
        XCTAssertNotNil(store.load().savedMapView)

        settings.savedMapView = nil
        store.save(settings)

        XCTAssertNil(store.load().savedMapView)
    }

    func testStoreIgnoresAHalfWrittenViewport() {
        let defaults = TestDefaults.make()
        defaults.set(
            ["latitude": 49.3960, "longitude": 15.5910],
            forKey: UserDefaultsAppSettingsStore.savedMapViewKey
        )

        XCTAssertNil(UserDefaultsAppSettingsStore(defaults: defaults).load().savedMapView)
    }

    func testStoreIgnoresAViewportThatIsNotMadeOfNumbers() {
        let defaults = TestDefaults.make()
        defaults.set(
            [
                "latitude": "somewhere",
                "longitude": 15.5910,
                "latitudeDelta": 0.09,
                "longitudeDelta": 0.138
            ],
            forKey: UserDefaultsAppSettingsStore.savedMapViewKey
        )

        XCTAssertNil(UserDefaultsAppSettingsStore(defaults: defaults).load().savedMapView)
    }

    // MARK: - Vehicles on the map

    func testStoreRoundTripsTheGroupingRadius() {
        let store = UserDefaultsAppSettingsStore(defaults: TestDefaults.make())
        XCTAssertEqual(store.load().clusterRadiusMetres, 0)

        var settings = AppSettings.default
        settings.clusterRadiusMetres = 250
        store.save(settings)

        XCTAssertEqual(store.load().clusterRadiusMetres, 250)

        settings.clusterRadiusMetres = 0
        store.save(settings)

        XCTAssertEqual(store.load().clusterRadiusMetres, 0)
    }

    func testARadiusOfNothingOrLessMeansNoGrouping() {
        XCTAssertEqual(AppSettings.clampedClusterRadius(0), 0)
        XCTAssertEqual(AppSettings.clampedClusterRadius(-100), 0)
        XCTAssertEqual(AppSettings.clampedClusterRadius(.nan), 0)
        XCTAssertEqual(AppSettings.clampedClusterRadius(.infinity), 0)
        XCTAssertEqual(AppSettings.clampedClusterRadius(100), 100)
        XCTAssertEqual(AppSettings.clampedClusterRadius(1.5), 1.5)
    }

    func testStoredRadiusIsValidatedOnTheWayIn() {
        let defaults = TestDefaults.make()
        defaults.set(-1.0, forKey: UserDefaultsAppSettingsStore.clusterRadiusMetresKey)

        XCTAssertEqual(UserDefaultsAppSettingsStore(defaults: defaults).load().clusterRadiusMetres, 0)
    }

    func testRadiusLabelsReadAsDistances() {
        XCTAssertEqual(PreferencesView.radiusLabel(0), String(localized: "Off"))
        XCTAssertEqual(PreferencesView.radiusLabel(250), "250 m")
        XCTAssertEqual(PreferencesView.radiusLabel(1_000), "1 km")
    }

    func testThePositionIsShownUnlessItIsSwitchedOff() {
        let store = UserDefaultsAppSettingsStore(defaults: TestDefaults.make())
        XCTAssertTrue(AppSettings.default.showsCurrentLocation)
        XCTAssertTrue(store.load().showsCurrentLocation)

        var settings = AppSettings.default
        settings.showsCurrentLocation = false
        store.save(settings)

        XCTAssertFalse(store.load().showsCurrentLocation)
    }

    func testFollowingIsOffByDefaultAndRemembered() {
        let store = UserDefaultsAppSettingsStore(defaults: TestDefaults.make())
        XCTAssertFalse(AppSettings.default.followsCurrentLocation)
        XCTAssertFalse(store.load().followsCurrentLocation)

        var settings = AppSettings.default
        settings.followsCurrentLocation = true
        store.save(settings)

        XCTAssertTrue(store.load().followsCurrentLocation)
    }

    // MARK: - Language

    func testLocalizationCodes() {
        XCTAssertEqual(AppLanguage.czech.localizationCode, "cs")
        XCTAssertEqual(AppLanguage.english.localizationCode, "en")
        XCTAssertNil(AppLanguage.system.localizationCode)
    }

    func testOverrideWritesTheChosenLanguageAndClearsItForSystem() {
        let defaults = TestDefaults.make()
        // What the device asks for before the app overrides anything. Removing
        // the override has to bring this back, which is how "follow the system"
        // works: `AppleLanguages` is read from the app's defaults first and from
        // the device afterwards.
        let deviceLanguages = TestDefaults.deviceLanguages(in: defaults)

        LanguageOverride.apply(.czech, to: defaults)
        XCTAssertEqual(defaults.array(forKey: LanguageOverride.defaultsKey) as? [String], ["cs"])

        LanguageOverride.apply(.english, to: defaults)
        XCTAssertEqual(defaults.array(forKey: LanguageOverride.defaultsKey) as? [String], ["en"])

        LanguageOverride.apply(.system, to: defaults)
        XCTAssertEqual(
            defaults.array(forKey: LanguageOverride.defaultsKey) as? [String],
            deviceLanguages
        )
    }

    // MARK: - Settings screen labels

    func testIntervalLabelsUseSecondsUpToAMinute() {
        XCTAssertEqual(PreferencesView.intervalLabel(5), "5 s")
        XCTAssertEqual(PreferencesView.intervalLabel(59), "59 s")
        XCTAssertEqual(PreferencesView.intervalLabel(60), "1 min")
        XCTAssertEqual(PreferencesView.intervalLabel(120), "2 min")
    }

    // MARK: - Refresh progress line

    func testProgressFollowsTheInterval() {
        XCTAssertEqual(RefreshProgressBar.progress(elapsed: 0, interval: 15), 0)
        XCTAssertEqual(RefreshProgressBar.progress(elapsed: 7.5, interval: 15), 0.5)
        XCTAssertEqual(RefreshProgressBar.progress(elapsed: 15, interval: 15), 1)
    }

    func testProgressNeverOverflowsOrGoesBackwards() {
        XCTAssertEqual(RefreshProgressBar.progress(elapsed: 90, interval: 15), 1)
        XCTAssertEqual(RefreshProgressBar.progress(elapsed: -4, interval: 15), 0)
        XCTAssertEqual(RefreshProgressBar.progress(elapsed: .infinity, interval: 15), 1)
        XCTAssertEqual(RefreshProgressBar.progress(elapsed: 5, interval: 0), 1)
    }
}
