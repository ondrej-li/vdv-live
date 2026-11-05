import XCTest
@testable import VdvLive

/// Why a line's timetable is not there, and what the app does about it.
@MainActor
final class TimetableDiagnosticsTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("timetable-diagnostics-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func archiveBytes() throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "jdf-archive-sample", withExtension: "zip")
        )
        return try Data(contentsOf: url)
    }

    private func store(mapping: [String: [String]],
                       published: StubTimetableMapping) throws -> LineTimetableStore {
        LineTimetableStore(
            client: StubTimetableArchive(archive: try archiveBytes()),
            mapping: mapping,
            files: TimetableFiles(directory: directory),
            mappingFetcher: published,
            mappingFiles: TimetableMappingFiles(directory: directory)
        )
    }

    private func offlineMapping() -> StubTimetableMapping {
        StubTimetableMapping(data: Data(), failure: TimetableError.transport("offline"))
    }

    /// What the archive republished at 20:50 does to an app built from the mapping
    /// of the publication before it: the entry it names now holds another line, so
    /// the line cannot be resolved - and the mapping published for the new archive
    /// is what fixes it.
    func testAStaleMappingIsReplacedAndTheLineResolves() async throws {
        let published = StubTimetableMapping(
            data: StubTimetableMapping.document(StubTimetableArchive.fixtureMapping)
        )
        let store = try store(mapping: ["764337": ["1.zip"]], published: published)
        await store.downloadIndex()

        let timetable = try await store.timetable(forLine: "764337")

        XCTAssertEqual(timetable?.lineNumber, "764337")
        XCTAssertEqual(published.calls.count, 1)
        guard case .published = store.mappingSource else {
            return XCTFail("Expected the published mapping to be in force")
        }
    }

    func testTheRefreshedMappingSurvivesARelaunch() async throws {
        let published = StubTimetableMapping(
            data: StubTimetableMapping.document(StubTimetableArchive.fixtureMapping)
        )
        let first = try store(mapping: ["764337": ["1.zip"]], published: published)
        await first.downloadIndex()
        _ = try await first.timetable(forLine: "764337")

        // A launch later: no mapping handed in, so whatever is on disk is used.
        let reopened = LineTimetableStore(
            client: StubTimetableArchive(archive: try archiveBytes()),
            files: TimetableFiles(directory: directory),
            mappingFetcher: offlineMapping(),
            mappingFiles: TimetableMappingFiles(directory: directory)
        )

        guard case .published = reopened.mappingSource else {
            return XCTFail("Expected the saved mapping to be read back")
        }
        await reopened.downloadIndex()
        let timetable = try await reopened.timetable(forLine: "764337")
        XCTAssertEqual(timetable?.lineNumber, "764337")
    }

    func testTheMappingIsRefreshedOncePerSession() async throws {
        let published = StubTimetableMapping(
            data: StubTimetableMapping.document(StubTimetableArchive.fixtureMapping)
        )
        let store = try store(mapping: ["764337": ["1.zip"], "764350": ["2.zip"]],
                              published: published)
        await store.downloadIndex()

        _ = try? await store.timetable(forLine: "764337")
        _ = try? await store.timetable(forLine: "764350")

        XCTAssertEqual(published.calls.count, 1)
    }

    func testDiagnosticsRecordWhatEachLineDid() async throws {
        let store = try store(mapping: StubTimetableArchive.fixtureMapping, published: offlineMapping())
        await store.downloadIndex()
        _ = try await store.timetable(forLine: "764337")

        let diagnostics = store.diagnostics()
        let line = try XCTUnwrap(diagnostics.lines.first { $0.lineNumber == "764337" })

        XCTAssertTrue(line.isDownloaded)
        XCTAssertEqual(line.record?.entryName, "7673.zip")
        XCTAssertEqual(line.record?.declaredLineNumber, "764337")
        XCTAssertEqual(line.candidates.first?.isInIndex, true)
        XCTAssertEqual(line.candidates.first?.isOnDisk, true)
        XCTAssertEqual(diagnostics.counts.downloaded, 1)
        XCTAssertEqual(diagnostics.archive.entryCount, 1)
    }

    func testDiagnosticsNameTheEntriesTheMappingAsksFor() async throws {
        let store = try store(mapping: ["764337": ["1.zip", "7673.zip"]], published: offlineMapping())
        await store.downloadIndex()

        let line = try XCTUnwrap(store.diagnostics().lines.first { $0.lineNumber == "764337" })

        // The fixture archive holds one entry; the other name is not in it.
        XCTAssertEqual(line.candidates.map(\.entryName), ["1.zip", "7673.zip"])
        XCTAssertEqual(line.candidates.map(\.isInIndex), [false, true])
    }

    func testForgettingTheArchiveForgetsTheRecords() async throws {
        let store = try store(mapping: StubTimetableArchive.fixtureMapping, published: offlineMapping())
        await store.downloadIndex()
        _ = try await store.timetable(forLine: "764337")
        XCTAssertEqual(store.diagnostics().cacheEntryCount, 1)

        store.forgetIndex()

        let diagnostics = store.diagnostics()
        XCTAssertEqual(diagnostics.cacheEntryCount, 0)
        XCTAssertTrue(diagnostics.lines.allSatisfy { $0.record == nil })
        XCTAssertEqual(diagnostics.archive.entryCount, 0)
    }

    func testTheSnapshotCanBePastedIntoABugReport() async throws {
        let store = try store(mapping: StubTimetableArchive.fixtureMapping, published: offlineMapping())
        await store.downloadIndex()
        _ = try await store.timetable(forLine: "764337")

        let text = store.diagnostics().text

        XCTAssertTrue(text.contains("764337"), text)
        XCTAssertTrue(text.contains("7673.zip"), text)
        XCTAssertTrue(text.contains("mapping: bundled"), text)
    }
}
