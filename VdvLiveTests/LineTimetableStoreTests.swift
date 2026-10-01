import XCTest
@testable import VdvLive

/// What the portal offers, unless a test says otherwise.
private let firstPublication = ArchiveVersion(
    etag: "\"a3306dce1451dd1:0\"",
    lastModified: Date(timeIntervalSince1970: 1_700_000_000),
    size: 106_230_086
)

/// The archive as it comes back after the portal has rebuilt it.
private let laterPublication = ArchiveVersion(
    etag: "\"a3306dce1451dd1:1\"",
    lastModified: Date(timeIntervalSince1970: 1_700_600_000),
    size: 106_230_099
)

@MainActor
final class LineTimetableStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("timetables-\(UUID().uuidString)", isDirectory: true)
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

    /// The fixture archive holds the entry for line 764337 only, under the last
    /// of the names the shipped mapping lists for that line: the entries before
    /// it are not in this archive, which the store has to cope with.
    private func makeStore(
        failures: Set<String> = [],
        version: ArchiveVersion = firstPublication,
        versionFails: Bool = false
    ) throws -> LineTimetableStore {
        LineTimetableStore(
            client: StubTimetableArchive(
                archive: try archiveBytes(),
                failures: failures,
                serverVersion: version,
                versionFails: versionFails
            ),
            files: TimetableFiles(directory: directory)
        )
    }

    func testNeedsTheIndexBeforeItCanAnswer() async throws {
        let store = try makeStore()

        XCTAssertFalse(store.isReady)

        do {
            _ = try await store.timetable(forLine: "764337")
            XCTFail("Expected the store to ask for the index first")
        } catch {
            XCTAssertEqual(error as? TimetableError, .notDownloaded)
        }
    }

    func testDownloadsTheIndexAndRemembersIt() async throws {
        let store = try makeStore()

        await store.downloadIndex()

        XCTAssertTrue(store.isReady)
        XCTAssertNotNil(store.downloadedAt)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.knownLineCount, 381)

        // A second store, as if the app had been launched again, reads it back.
        let reopened = try makeStore()
        XCTAssertTrue(reopened.isReady)
        XCTAssertNotNil(reopened.downloadedAt)
    }

    func testReadsALineOutOfTheArchive() async throws {
        let store = try makeStore()
        await store.downloadIndex()

        let fetched = try await store.timetable(forLine: "764337")
        let timetable = try XCTUnwrap(fetched)

        XCTAssertEqual(timetable.lineNumber, "764337")
        XCTAssertEqual(timetable.displayNumber, "337")
        XCTAssertEqual(timetable.routeName, "Třešť-Brtnice-Okříšky-Radonín")
        XCTAssertEqual(timetable.operatorName, "ČSAD AUTOBUSY České Budějovice a.s.")
        XCTAssertNotNil(timetable.run(serviceNumber: "1"))
    }

    func testCachesTheEntryOnDisk() async throws {
        let store = try makeStore()
        await store.downloadIndex()
        _ = try await store.timetable(forLine: "764337")

        let cached = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(cached.contains { $0.hasPrefix("entry-") }, "\(cached)")

        // A store that cannot reach the archive at all still answers, because
        // the entry is already on disk - only the index has to be in memory.
        let offline = LineTimetableStore(
            client: StubTimetableArchive(archive: Data(), failures: ["*"]),
            files: TimetableFiles(directory: directory)
        )
        let fetched = try await offline.timetable(forLine: "764337")
        let timetable = try XCTUnwrap(fetched)
        XCTAssertEqual(timetable.displayNumber, "337")
    }

    func testReturnsNothingForALineThatIsNotPublished() async throws {
        let store = try makeStore()
        await store.downloadIndex()

        let timetable = try await store.timetable(forLine: "999999")

        XCTAssertNil(timetable)
    }

    func testRefusesAnEntryThatHoldsAnotherLine() async throws {
        // Asking for a line the mapping knows, but whose entries are not in this
        // archive: the only entry here belongs to 764337, so the line number in
        // its Linky.txt has to be noticed and the answer refused.
        let store = LineTimetableStore(
            client: StubTimetableArchive(archive: try archiveBytes()),
            mapping: ["764931": [try fixtureEntryName()]],
            files: TimetableFiles(directory: directory)
        )
        await store.downloadIndex()

        do {
            _ = try await store.timetable(forLine: "764931")
            XCTFail("Expected the mismatch to be noticed")
        } catch {
            XCTAssertEqual(error as? TimetableError, .lineNotInArchive("764931"))
        }
    }

    func testReportsAFailedIndexDownload() async throws {
        let store = try makeStore(failures: ["*"])

        await store.downloadIndex()

        XCTAssertFalse(store.isReady)
        XCTAssertNotNil(store.errorMessage)
    }

    func testForgettingTheIndexClearsEverything() async throws {
        let store = try makeStore()
        await store.downloadIndex()
        _ = try await store.timetable(forLine: "764337")

        store.forgetIndex()

        XCTAssertFalse(store.isReady)
        XCTAssertNil(store.downloadedAt)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertTrue(left.isEmpty, "\(left)")
    }

    /// The name the fixture archive lists its one entry under. The mapping the
    /// app ships with names the same entry, and the assertions below keep the
    /// two in step: the archive reassigns these names when it is republished, so
    /// refreshing the mapping means refreshing the fixture with it.
    private func fixtureEntryName() throws -> String {
        let entries = try ZipArchive.entries(in: try archiveBytes())
        return try XCTUnwrap(entries.first).name
    }

    func testShipsAMappingForTheRegion() throws {
        // The test host is the app, so this reads the file the app is built with.
        let mapping = LineTimetableStore.bundledMapping()

        XCTAssertFalse(mapping.isEmpty)
        XCTAssertEqual(mapping.count, 381)

        // One line of it, against the archive the other tests use: the mapping
        // has to name the entry the archive really holds the line in, and it has
        // to offer a candidate before that one, so the fallback is exercised.
        let candidates = try XCTUnwrap(mapping["764337"])
        XCTAssertTrue(candidates.contains(try fixtureEntryName()), "\(candidates)")
        XCTAssertGreaterThan(candidates.count, 1)
    }

    // MARK: - Is the index still the published one?

    func testDownloadingTheIndexRecordsWhichArchiveItCameFrom() async throws {
        let store = try makeStore()

        await store.downloadIndex()

        XCTAssertEqual(store.update, .upToDate)
        XCTAssertEqual(store.archivePublishedAt, firstPublication.lastModified)

        // A second store, as if the app had been launched again, knows too.
        let reopened = try makeStore()
        XCTAssertEqual(reopened.archivePublishedAt, firstPublication.lastModified)
    }

    func testCheckingForUpdatesOnTheSameArchiveSaysSo() async throws {
        let store = try makeStore()
        await store.downloadIndex()

        await store.checkForUpdates()

        XCTAssertEqual(store.update, .upToDate)
        XCTAssertNil(store.errorMessage)
    }

    func testCheckingForUpdatesFindsANewerArchive() async throws {
        let downloaded = try makeStore()
        await downloaded.downloadIndex()

        // The same files on disk, with the portal having rebuilt the archive in
        // the meantime, which is the whole point of asking.
        let later = try makeStore(version: laterPublication)

        await later.checkForUpdates()

        XCTAssertEqual(later.update, .outdated)
        XCTAssertNil(later.errorMessage)
    }

    func testUpdatingReadsTheIndexAgainAndThenReportsUpToDate() async throws {
        let downloaded = try makeStore()
        await downloaded.downloadIndex()
        let later = try makeStore(version: laterPublication)
        await later.checkForUpdates()
        XCTAssertEqual(later.update, .outdated)

        await later.downloadIndex()

        XCTAssertEqual(later.update, .upToDate)
        XCTAssertEqual(later.archivePublishedAt, laterPublication.lastModified)
    }

    func testAnEtagThatMatchesIsTheSameArchiveWhateverTheDate() async throws {
        let downloaded = try makeStore()
        await downloaded.downloadIndex()

        // The same identity with a date that moved and a size that grew: the
        // ETag is the file's identity, so this is still the index that was read.
        let probed = try makeStore(version: ArchiveVersion(
            etag: firstPublication.etag,
            lastModified: Date(timeIntervalSince1970: 1_700_600_000),
            size: 106_999_999
        ))

        await probed.checkForUpdates()

        XCTAssertEqual(probed.update, .upToDate)
    }

    func testAnArchiveWithTheSameDateIsTheSameOneWhateverItsSize() async throws {
        let downloaded = try makeStore(version: ArchiveVersion(
            etag: nil,
            lastModified: firstPublication.lastModified,
            size: 106_230_086
        ))
        await downloaded.downloadIndex()

        // A server that gives no ETag: the date is the next best signal, and the
        // size the last resort.
        let probed = try makeStore(version: ArchiveVersion(
            etag: nil,
            lastModified: firstPublication.lastModified,
            size: 106_230_099
        ))

        await probed.checkForUpdates()

        XCTAssertEqual(probed.update, .upToDate)
    }

    func testAFailedCheckLeavesTheIndexAloneAndSaysWhy() async throws {
        let store = try makeStore()
        await store.downloadIndex()
        let offline = try makeStore(failures: ["*"])

        await offline.checkForUpdates()

        XCTAssertTrue(offline.isReady, "the index is still usable")
        XCTAssertNotNil(offline.errorMessage)
        XCTAssertEqual(offline.update, .unchecked, "nothing was learned")
    }

    func testAnIndexStoredWithoutAVersionCannotBeCompared() async throws {
        // The shape an index has when it was stored before the app recorded which
        // archive it came from.
        let files = TimetableFiles(directory: directory)
        files.saveIndex(try ZipArchive.entries(in: try archiveBytes()), date: Date())
        let store = try makeStore()

        await store.checkForUpdates()

        XCTAssertEqual(store.update, .cannotTell)
        XCTAssertNil(store.errorMessage, "not a failure, only an unknown")
        XCTAssertTrue(store.isReady)
    }

    func testADownloadThatCannotIdentifyTheArchiveStillWorks() async throws {
        let store = try makeStore(versionFails: true)

        await store.downloadIndex()

        XCTAssertTrue(store.isReady)
        XCTAssertEqual(store.update, .cannotTell)
        XCTAssertNil(store.errorMessage, "the download itself succeeded")
    }

    func testForgettingTheIndexForgetsWhichArchiveItCameFrom() async throws {
        let store = try makeStore()
        await store.downloadIndex()
        XCTAssertNotNil(store.archivePublishedAt)

        store.forgetIndex()

        XCTAssertNil(store.archivePublishedAt)
        XCTAssertEqual(store.update, .unchecked)
        XCTAssertNil(try makeStore().archivePublishedAt)
    }
}
