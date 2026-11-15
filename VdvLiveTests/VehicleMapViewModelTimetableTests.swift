import XCTest
@testable import VdvLive

/// The timetable side of the detail card: it should appear once the index has
/// been downloaded, and stay out of the way until then.
@MainActor
final class VehicleMapViewModelTimetableTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vm-timetables-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// The archive fixture holds line 764337, run 1.
    private func makeStore(downloaded: Bool) async throws -> LineTimetableStore {
        let store = LineTimetableStore(
            client: try StubTimetableArchive.fromFixture(),
            mapping: StubTimetableArchive.fixtureMapping,
            files: TimetableFiles(directory: directory)
        )
        if downloaded {
            await store.downloadIndex()
        }
        return store
    }

    private func makeViewModel(store: LineTimetableStore) -> VehicleMapViewModel {
        let detail = VehicleDetail(
            lineCode: LineCode(raw: "764337"),
            serviceNumber: "1",
            isBarrierFree: nil,
            stopName: "Třešť,nám.",
            reportedDelayMinutes: 3,
            runStops: []
        )
        return VehicleMapViewModel(
            payloadStore: InMemoryVehiclePayloadStore(),
            fetcher: StubVehicleFetcher(vehicles: [Fixture.vehicle(id: 1, line: "766420")]),
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(detail: detail),
            timetables: store,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    /// The card draws the run the popup names - which is the whole stop list. The
    /// regression here read as "the timetables are not downloaded": the popup's
    /// markup had changed, the run came back nil, and a card with no run drew
    /// nothing at all.
    func testTheCardHasARunToDrawWhenThePopupNamesOne() async throws {
        // The line the popup fixture names is 766420, so that is the line the
        // timetable has to be about.
        let package = ZipFixture.linePackage(lineNumber: "766420",
                                             runs: [("109", "0435"), ("110", "1730")])
        let archive = ZipFixture.archive(entries: [("a.zip", package)])
        let store = LineTimetableStore(
            client: StubTimetableArchive(archive: archive),
            mapping: ["766420": ["a.zip"]],
            files: TimetableFiles(directory: directory),
            mappingFetcher: StubTimetableMapping(data: Data(),
                                                 failure: TimetableError.transport("offline")),
            mappingFiles: TimetableMappingFiles(directory: directory)
        )
        await store.downloadIndex()

        // The popup the site renders today: `Linka / spoj` → `764337 / 109`.
        let info = try VehicleDetailHTMLParser.parseInfoWindow(SampleDetailHTML.infoWindowFacts)
        let detail = VehicleDetail(lineCode: LineCode(raw: try XCTUnwrap(info.line)),
                                   serviceNumber: info.serviceNumber,
                                   isBarrierFree: info.isBarrierFree,
                                   stopName: info.stopName,
                                   reportedDelayMinutes: info.reportedDelayMinutes,
                                   runStops: [])
        let viewModel = VehicleMapViewModel(
            payloadStore: InMemoryVehiclePayloadStore(),
            fetcher: StubVehicleFetcher(vehicles: [Fixture.vehicle(id: 1, line: "766420")]),
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(detail: detail),
            timetables: store,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        await viewModel.load()
        await viewModel.loadDetail(for: Fixture.vehicle(id: 1, line: "766420"))

        XCTAssertEqual(viewModel.timetableRun?.serviceNumber, "109")
        XCTAssertNil(viewModel.timetableNote, "there is a run, so there is nothing to explain")
        XCTAssertNil(viewModel.timetableError)
    }

    func testLoadsTheTimetableOfTheSelectedRun() async throws {
        let store = try await makeStore(downloaded: true)
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        await viewModel.loadDetail(for: Fixture.vehicle(id: 1, line: "764337"))

        let timetable = try XCTUnwrap(viewModel.lineTimetable)
        XCTAssertEqual(timetable.lineNumber, "764337")
        XCTAssertEqual(timetable.displayNumber, "337")
        let run = try XCTUnwrap(timetable.run(serviceNumber: "1"))
        XCTAssertEqual(run.calls.first?.time?.text, "04:35")
        XCTAssertNil(viewModel.timetableError)
        XCTAssertFalse(viewModel.isLoadingTimetable)
    }

    func testSaysTheTimetableIsNotDownloadedYet() async throws {
        let store = try await makeStore(downloaded: false)
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        await viewModel.loadDetail(for: Fixture.vehicle(id: 1, line: "764337"))

        XCTAssertNil(viewModel.lineTimetable)
        XCTAssertFalse(viewModel.isLoadingTimetable)
        // The card cannot draw a timetable, so it has to say why. Being silent here
        // is what made the feature look as though it did not exist.
        XCTAssertEqual(viewModel.timetableError, TimetableError.notDownloaded.errorDescription)
    }

    func testPicksTheTimetableUpAfterTheIndexArrives() async throws {
        let store = try await makeStore(downloaded: false)
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        await viewModel.loadDetail(for: Fixture.vehicle(id: 1, line: "764337"))
        XCTAssertNil(viewModel.lineTimetable)

        // What the settings screen does once the download finishes.
        await store.downloadIndex()
        await viewModel.reloadTimetableForSelection()

        XCTAssertEqual(viewModel.lineTimetable?.displayNumber, "337")
    }

    func testForgettingTheTimetablesClearsTheCard() async throws {
        let store = try await makeStore(downloaded: true)
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        await viewModel.loadDetail(for: Fixture.vehicle(id: 1, line: "764337"))
        XCTAssertNotNil(viewModel.lineTimetable)

        viewModel.forgetTimetables()

        XCTAssertNil(viewModel.lineTimetable)
        XCTAssertFalse(store.isReady)
    }

    func testSelectingAnotherVehicleReplacesTheTimetable() async throws {
        let store = try await makeStore(downloaded: true)
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        await viewModel.loadDetail(for: Fixture.vehicle(id: 1, line: "764337"))
        XCTAssertEqual(viewModel.lineTimetable?.displayNumber, "337")

        // A vehicle on a line the shipped mapping does not know.
        let unknown = VehicleDetail(
            lineCode: LineCode(raw: "999999"),
            serviceNumber: "1",
            isBarrierFree: nil,
            stopName: nil,
            reportedDelayMinutes: nil,
            runStops: []
        )
        let other = VehicleMapViewModel(
            payloadStore: InMemoryVehiclePayloadStore(),
            fetcher: StubVehicleFetcher(vehicles: [Fixture.vehicle(id: 2, line: "999999")]),
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(detail: unknown),
            timetables: store,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        await other.load()
        await other.loadDetail(for: Fixture.vehicle(id: 2, line: "999999"))

        XCTAssertNil(other.lineTimetable)
        XCTAssertEqual(
            other.timetableError,
            String(localized: "Timetable for this service is not available.")
        )
    }

    func testReportsAnArchiveFailure() async throws {
        let store = LineTimetableStore(
            client: StubTimetableArchive(archive: Data(), failures: ["*"]),
            files: TimetableFiles(directory: directory)
        )
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        // No index: the card has nothing to add, and says so rather than nothing.
        await viewModel.loadDetail(for: Fixture.vehicle(id: 1, line: "764337"))
        XCTAssertNil(viewModel.lineTimetable)
        XCTAssertEqual(viewModel.timetableError, TimetableError.notDownloaded.errorDescription)

        // A download that fails leaves no index, so the card keeps saying that,
        // and the store's own message is what the settings screen reports.
        await store.downloadIndex()
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(viewModel.timetableError, TimetableError.notDownloaded.errorDescription)
    }
}
