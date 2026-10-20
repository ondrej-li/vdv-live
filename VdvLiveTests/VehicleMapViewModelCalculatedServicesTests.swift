import XCTest
@testable import VdvLive

/// The map's side of #94: what the timetable expects is drawn once the timetables
/// are here and the user asked for it, and nothing is drawn otherwise.
@MainActor
final class VehicleMapViewModelCalculatedServicesTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vm-calculated-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// 04:40 in Prague, which run 1 of the fixture line is in the middle of.
    private var morning: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ExpectedServices.regionTimeZone
        return calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 20, hour: 4, minute: 40
        ))!
    }

    private func makeStore(downloaded: Bool = true) async throws -> LineTimetableStore {
        let store = LineTimetableStore(
            client: try StubTimetableArchive.fromFixture(),
            files: TimetableFiles(directory: directory)
        )
        if downloaded {
            await store.downloadIndex()
        }
        return store
    }

    private func makeViewModel(
        store: LineTimetableStore,
        showsCalculatedServices: Bool,
        vehicles: [Vehicle] = [Fixture.vehicle(id: 1, line: "841334")],
        favourites: FavouriteLines = FavouriteLines()
    ) -> VehicleMapViewModel {
        var settings = AppSettings.default
        settings.showsCalculatedServices = showsCalculatedServices

        return VehicleMapViewModel(
            payloadStore: InMemoryVehiclePayloadStore(),
            fetcher: StubVehicleFetcher(vehicles: vehicles),
            favouriteLinesStore: InMemoryFavouriteLinesStore(lines: favourites),
            settingsStore: InMemoryAppSettingsStore(settings: settings),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(detail: nil),
            timetables: store,
            now: { [morning] in morning }
        )
    }

    /// Reads the fixture line's timetable, then lets a payload rebuild the map.
    private func loadTimetableAndRefresh(_ viewModel: VehicleMapViewModel) async {
        await viewModel.load()
        await viewModel.loadTimetable(forLine: "764337", serviceNumber: "1")
        await viewModel.load()
    }

    // MARK: - What is drawn

    func testShowsAServiceTheFeedIsNotReporting() async throws {
        let store = try await makeStore()
        let viewModel = makeViewModel(store: store, showsCalculatedServices: true)

        await loadTimetableAndRefresh(viewModel)

        let service = try XCTUnwrap(viewModel.calculatedServices.first)
        XCTAssertEqual(viewModel.calculatedServices.count, 1)
        XCTAssertEqual(service.displayLine, "337")
        XCTAssertEqual(service.serviceNumber, "1")
        // The fixture run calls at 04:35 and 04:39 before heading on, so 04:40 puts
        // the marker at the second of them.
        XCTAssertEqual(service.stopName, "Třešť,Pouště")
        XCTAssertEqual(service.scheduledTime, TimeOfDay(minutes: 4 * 60 + 39))
    }

    func testDrawsNothingForALineTheFeedReports() async throws {
        let store = try await makeStore()
        let viewModel = makeViewModel(
            store: store,
            showsCalculatedServices: true,
            vehicles: [Fixture.vehicle(id: 1, line: "764337")]
        )

        await loadTimetableAndRefresh(viewModel)

        XCTAssertTrue(viewModel.calculatedServices.isEmpty)
    }

    func testDrawsNothingWhenTheSettingIsOff() async throws {
        let store = try await makeStore()
        let viewModel = makeViewModel(store: store, showsCalculatedServices: false)

        await loadTimetableAndRefresh(viewModel)

        XCTAssertTrue(viewModel.calculatedServices.isEmpty)
    }

    func testDrawsNothingBeforeTheIndexIsDownloaded() async throws {
        let store = try await makeStore(downloaded: false)
        let viewModel = makeViewModel(store: store, showsCalculatedServices: true)

        await loadTimetableAndRefresh(viewModel)

        XCTAssertTrue(viewModel.calculatedServices.isEmpty)
    }

    // MARK: - What it keeps up with

    func testDropsThemWhenTheTimetablesAreRemoved() async throws {
        let store = try await makeStore()
        let viewModel = makeViewModel(store: store, showsCalculatedServices: true)
        await loadTimetableAndRefresh(viewModel)
        XCTAssertFalse(viewModel.calculatedServices.isEmpty)

        viewModel.forgetTimetables()

        XCTAssertTrue(viewModel.calculatedServices.isEmpty)
    }

    func testTractionFilterLeavesThemOut() async throws {
        let store = try await makeStore()
        let viewModel = makeViewModel(store: store, showsCalculatedServices: true)
        await loadTimetableAndRefresh(viewModel)
        XCTAssertFalse(viewModel.calculatedServices.isEmpty)

        // The archive says nothing about how a line is worked, so a calculated
        // service cannot answer a traction filter and must not pretend to.
        viewModel.select(filter: .traction(.bus))

        XCTAssertTrue(viewModel.calculatedServices.isEmpty)
    }

    func testPinnedFilterKeepsOnlyPinnedLines() async throws {
        let store = try await makeStore()
        let viewModel = makeViewModel(store: store, showsCalculatedServices: true)
        await loadTimetableAndRefresh(viewModel)

        viewModel.setShowsOnlyPinnedLines(true)
        XCTAssertTrue(viewModel.calculatedServices.isEmpty)

        viewModel.pin(line: "764337")
        XCTAssertEqual(viewModel.calculatedServices.map(\.displayLine), ["337"])
    }

    func testTurningTheSettingOffDropsThemAndTurningItOnBringsThemBack() async throws {
        let store = try await makeStore()
        let viewModel = makeViewModel(store: store, showsCalculatedServices: false)
        await loadTimetableAndRefresh(viewModel)
        XCTAssertTrue(viewModel.calculatedServices.isEmpty)

        viewModel.setShowsCalculatedServices(true)
        XCTAssertEqual(viewModel.calculatedServices.map(\.displayLine), ["337"])

        viewModel.setShowsCalculatedServices(false)
        XCTAssertTrue(viewModel.calculatedServices.isEmpty)
    }

    func testTheSettingIsRemembered() async throws {
        let store = try await makeStore()
        let store0 = InMemoryAppSettingsStore(settings: AppSettings.default)
        let viewModel = VehicleMapViewModel(
            payloadStore: InMemoryVehiclePayloadStore(),
            fetcher: StubVehicleFetcher(vehicles: [Fixture.vehicle(id: 1)]),
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: store0,
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(detail: nil),
            timetables: store,
            now: { [morning] in morning }
        )

        viewModel.setShowsCalculatedServices(true)

        XCTAssertTrue(store0.load().showsCalculatedServices)
    }
}
