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

    // MARK: - Noticing a mapping that lags behind the index

    /// A mapping an earlier launch saved from the site, built from a publication of
    /// its own - which is how a device ends up with an index newer than its mapping.
    private func savePublishedMapping(_ lines: [String: [String]], archive: [String: Any]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = StubTimetableMapping.document(lines, archive: archive)
        try document.write(to: directory.appendingPathComponent("jdf-lines.json"))
    }

    /// A store that reads whatever mapping is on disk, as a launch does.
    private func makeStore(published: StubTimetableMapping? = nil) throws -> LineTimetableStore {
        LineTimetableStore(
            client: StubTimetableArchive(archive: try archiveBytes()),
            files: TimetableFiles(directory: directory),
            mappingFetcher: published ?? offlineMapping(),
            mappingFiles: TimetableMappingFiles(directory: directory)
        )
    }

    /// The archive republished, so the index on the phone names entries the mapping
    /// does not: that is every line failing at once, and one request fixes it.
    func testAStaleMappingIsRefreshedAsSoonAsTheIndexIsRead() async throws {
        try savePublishedMapping(["764337": ["1.zip"]],
                                 archive: ["bytes": 106_114_117, "etag": "\"a3306dce1451dd1:-1\""])
        let published = StubTimetableMapping(
            data: StubTimetableMapping.document(StubTimetableArchive.fixtureMapping,
                                                archive: ["bytes": 106_230_086,
                                                          "etag": "\"a3306dce1451dd1:0\""])
        )
        let store = try makeStore(published: published)

        await store.downloadIndex()

        XCTAssertEqual(published.calls.count, 1, "the launch check must not wait for a line to fail")
        XCTAssertEqual(store.mappingFreshness, .current)

        let timetable = try await store.timetable(forLine: "764337")
        XCTAssertEqual(timetable?.lineNumber, "764337")
    }

    /// A mapping built from the archive the index describes is left alone: the check
    /// costs nothing when nothing has changed.
    func testAMappingThatMatchesTheIndexIsNotAskedForAgain() async throws {
        try savePublishedMapping(StubTimetableArchive.fixtureMapping,
                                 archive: ["bytes": 106_230_086,
                                           "etag": "\"a3306dce1451dd1:0\""])
        let published = StubTimetableMapping(
            data: StubTimetableMapping.document(StubTimetableArchive.fixtureMapping,
                                                archive: ["bytes": 106_230_086])
        )
        let store = try makeStore(published: published)
        await store.downloadIndex()

        XCTAssertEqual(published.calls.count, 0, "a current mapping is not downloaded again")
        XCTAssertEqual(store.mappingFreshness, .current)

        // A launch later, with the same published mapping saved on disk.
        let reopened = try makeStore(published: published)
        await reopened.downloadIndex()

        XCTAssertEqual(published.calls.count, 0)
        XCTAssertEqual(reopened.mappingFreshness, .current)
    }

    /// The mapping says nothing about which archive it came from, so nothing can be
    /// claimed about it either way - and nothing is fetched on the strength of a
    /// guess.
    func testAMappingWithoutAnIdentityIsNeitherCurrentNorStale() async throws {
        // A mapping written before the builder recorded which archive it came from.
        try savePublishedMapping(StubTimetableArchive.fixtureMapping, archive: [:])
        let published = StubTimetableMapping(
            data: StubTimetableMapping.document(StubTimetableArchive.fixtureMapping)
        )
        let store = try makeStore(published: published)
        await store.downloadIndex()

        XCTAssertEqual(store.mappingFreshness, .unknown)
        XCTAssertEqual(published.calls.count, 0)
    }

    func testTheSnapshotNamesThePublicationTheMappingWasBuiltFor() async throws {
        try savePublishedMapping(["764337": ["1.zip"]],
                                 archive: ["bytes": 106_114_117, "date": "06112026"])
        let published = StubTimetableMapping(
            data: StubTimetableMapping.document(StubTimetableArchive.fixtureMapping,
                                                archive: ["bytes": 1, "date": "12112026"])
        )
        let store = try makeStore(published: published)
        await store.downloadIndex()

        let text = store.diagnostics().text

        XCTAssertTrue(text.contains("mapping archive:"), text)
        XCTAssertTrue(text.contains("12112026"), text)
        XCTAssertTrue(text.contains("mapping freshness: STALE"), text)
    }

    // MARK: - What is on the phone

    func testEveryCachedFileIsReportedWithTheLineItDeclares() async throws {
        let store = try store(mapping: StubTimetableArchive.fixtureMapping, published: offlineMapping())
        await store.downloadIndex()
        _ = try await store.timetable(forLine: "764337")

        let diagnostics = store.diagnostics()
        let file = try XCTUnwrap(diagnostics.cacheFiles.first)

        XCTAssertEqual(file.name, "7673.zip")
        XCTAssertEqual(file.declaredLine, "764337")
        XCTAssertEqual(file.servedLine, "764337")
        XCTAssertTrue(file.isInIndex)
        XCTAssertGreaterThan(file.bytes, 0)
    }

    /// The line, the files inside its entry, and the timetable read back out of them:
    /// this is what the browse screen lists, and it must not touch the network.
    func testDownloadedLinesCarryTheirFilesAndTheirRuns() async throws {
        let store = try store(mapping: StubTimetableArchive.fixtureMapping, published: offlineMapping())
        await store.downloadIndex()
        _ = try await store.timetable(forLine: "764337")

        // A store that cannot reach anything at all still lists what is on disk.
        let offline = LineTimetableStore(
            client: StubTimetableArchive(archive: Data(), failures: ["*"]),
            mapping: StubTimetableArchive.fixtureMapping,
            files: TimetableFiles(directory: directory),
            mappingFetcher: offlineMapping(),
            mappingFiles: TimetableMappingFiles(directory: directory)
        )
        await offline.downloadIndex()

        let line = try XCTUnwrap(offline.downloadedTimetables().first { $0.lineNumber == "764337" })
        XCTAssertEqual(line.entryName, "7673.zip")
        XCTAssertEqual(line.timetable.displayNumber, "337")
        XCTAssertEqual(line.runs.count, 18)
        XCTAssertGreaterThan(line.stopCount, 10)
        XCTAssertNotNil(line.spanText)
        XCTAssertTrue(line.sourceFiles.contains { $0.name == "Linky.txt" })
        XCTAssertTrue(line.sourceFiles.contains { $0.name == "Zasspoje.txt" })
        XCTAssertGreaterThan(line.totalSourceBytes, 0)
    }

    func testTheSourceOfADownloadedLineIsTheTextTheArchiveHolds() async throws {
        let store = try store(mapping: StubTimetableArchive.fixtureMapping, published: offlineMapping())
        await store.downloadIndex()
        _ = try await store.timetable(forLine: "764337")

        let linky = try XCTUnwrap(store.sourceText(ofEntryNamed: "7673.zip", file: "Linky.txt"))

        XCTAssertTrue(linky.contains("\"764337\""), linky)
        XCTAssertTrue(linky.contains("Třešť-Brtnice-Okříšky-Radonín"), linky)
    }

    /// The archive renumbers entries, so a file cached for the previous publication
    /// is no longer named by the mapping. It is still the line's timetable, and a
    /// timetable a few days old beats "not in the published timetable".
    func testACachedEntryAnswersForALineTheArchiveHasRenumbered() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entryBytes = try Data(contentsOf: try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "jdf-line-764337", withExtension: "zip")
        ))
        try entryBytes.write(to: directory.appendingPathComponent("entry-1.zip"))

        let store = try store(mapping: ["764337": ["1.zip"]], published: offlineMapping())
        await store.downloadIndex()

        let timetable = try await store.timetable(forLine: "764337")

        XCTAssertEqual(timetable?.lineNumber, "764337")
        let record = try XCTUnwrap(store.diagnostics().lines.first { $0.lineNumber == "764337" }?.record)
        XCTAssertEqual(record.entryName, "1.zip")
        XCTAssertEqual(record.isFromEarlierArchive, true)
        XCTAssertEqual(store.diagnostics().downloaded.first?.isFromEarlierArchive, true)
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
