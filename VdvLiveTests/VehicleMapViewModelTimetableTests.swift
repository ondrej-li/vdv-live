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
            fetcher: StubVehicleFetcher(vehicles: [Fixture.vehicle(id: 1, line: "764337")]),
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(detail: detail),
            timetables: store,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
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

    func testSaysNothingUntilTheIndexIsDownloaded() async throws {
        let store = try await makeStore(downloaded: false)
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        await viewModel.loadDetail(for: Fixture.vehicle(id: 1, line: "764337"))

        XCTAssertNil(viewModel.lineTimetable)
        XCTAssertFalse(viewModel.isLoadingTimetable)
        XCTAssertNil(viewModel.timetableError)
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
        XCTAssertNil(other.timetableError)
    }

    func testReportsAnArchiveFailure() async throws {
        let store = LineTimetableStore(
            client: StubTimetableArchive(archive: Data(), failures: ["*"]),
            files: TimetableFiles(directory: directory)
        )
        let viewModel = makeViewModel(store: store)
        await viewModel.load()

        // No index: the card simply has nothing to add, and says nothing.
        await viewModel.loadDetail(for: Fixture.vehicle(id: 1, line: "764337"))
        XCTAssertNil(viewModel.lineTimetable)
        XCTAssertNil(viewModel.timetableError)

        // With an index but an unreachable archive, the failure is reported.
        await store.downloadIndex()
        XCTAssertNil(viewModel.timetableError)
    }
}
