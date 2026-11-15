import XCTest
@testable import VdvLive

/// What a line looks like in the archive, and what the card asks for.
@MainActor
final class TimetableVariantResolutionTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("variants-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// Line 764337 as the archive publishes it: the current validity period, which
    /// does not have run 38, and an older one that does. A phone that reads the line
    /// without asking for a run caches the current period - and the card, which does
    /// ask, used to be answered from that cache and then have no run to draw.
    private func archive() -> Data {
        let current = ZipFixture.linePackage(lineNumber: "764337",
                                             runs: [("1", "0435"), ("2", "1010")],
                                             validFrom: "01102026")
        let older = ZipFixture.linePackage(lineNumber: "764337",
                                           runs: [("38", "1730")],
                                           validFrom: "14122025")
        return ZipFixture.archive(entries: [("a.zip", current), ("b.zip", older)])
    }

    private func store() -> LineTimetableStore {
        LineTimetableStore(
            client: StubTimetableArchive(archive: archive()),
            mapping: ["764337": ["a.zip", "b.zip"]],
            files: TimetableFiles(directory: directory),
            mappingFetcher: StubTimetableMapping(data: Data(),
                                                 failure: TimetableError.transport("offline")),
            mappingFiles: TimetableMappingFiles(directory: directory)
        )
    }

    /// The bug: the line was read once without a run, the card asked for run 38,
    /// and the answer was the cached period that has no such run - so the card drew
    /// nothing at all.
    func testARunIsFoundInAnotherPeriodEvenWhenOneIsAlreadyCached() async throws {
        let store = store()
        await store.downloadIndex()

        let withoutRun = try await store.timetable(forLine: "764337")
        XCTAssertNotNil(withoutRun?.run(serviceNumber: "1"), "the current period is cached first")
        XCTAssertNil(withoutRun?.run(serviceNumber: "38"))

        let withRun = try await store.timetable(forLine: "764337", serviceNumber: "38")

        XCTAssertEqual(withRun?.run(serviceNumber: "38")?.serviceNumber, "38",
                       "the period holding the run asked for has to be read")
    }

    /// A line whose periods know nothing of the run still answers with the line:
    /// the run is missing, not the line.
    func testALineIsStillReadWhenNoPeriodHasTheRun() async throws {
        let store = store()
        await store.downloadIndex()

        let timetable = try await store.timetable(forLine: "764337", serviceNumber: "999")

        XCTAssertNotNil(timetable, "a missing run is not a missing line")
        XCTAssertNil(timetable?.run(serviceNumber: "999"))
    }

    /// The ordinary case still works after the line has been read without a run:
    /// the run the vehicle is on is found where it always was.
    func testTheRunIsFoundAfterTheLineWasReadWithoutOne() async throws {
        let store = store()
        await store.downloadIndex()

        _ = try await store.timetable(forLine: "764337")

        let timetable = try await store.timetable(forLine: "764337", serviceNumber: "1")

        XCTAssertEqual(timetable?.run(serviceNumber: "1")?.serviceNumber, "1")
    }

    /// And the card has something to say in that case rather than drawing nothing.
    func testTheCardExplainsARunThatIsNotInTheTimetable() async throws {
        let store = store()
        await store.downloadIndex()
        let detail = VehicleDetail(lineCode: LineCode(raw: "764337"),
                                   serviceNumber: "999",
                                   isBarrierFree: nil,
                                   stopName: "Testov,nám.",
                                   reportedDelayMinutes: 0,
                                   runStops: [])
        let viewModel = VehicleMapViewModel(
            payloadStore: InMemoryVehiclePayloadStore(),
            fetcher: StubVehicleFetcher(vehicles: [Fixture.vehicle(id: 1, line: "764337")]),
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(detail: detail),
            timetables: store,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        await viewModel.load()
        await viewModel.loadDetail(for: Fixture.vehicle(id: 1, line: "764337"))

        XCTAssertNotNil(viewModel.lineTimetable, "the timetable is there")
        XCTAssertNil(viewModel.timetableError)
        XCTAssertNotNil(viewModel.timetableNote, "and the card has to say why it is empty")
    }
}
