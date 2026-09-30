import XCTest
@testable import VdvMap

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

    /// The fixture archive holds the entry for line 764337 only. The mapping
    /// that ships with the app also lists a second entry for it (4861.zip),
    /// which this archive does not have - the store has to cope with that.
    private func makeStore(failures: Set<String> = []) throws -> LineTimetableStore {
        LineTimetableStore(
            client: StubTimetableArchive(archive: try archiveBytes(), failures: failures),
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
            mapping: ["764931": ["853.zip"]],
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

    func testShipsAMappingForTheRegion() {
        // The test host is the app, so this reads the file the app is built with.
        let mapping = LineTimetableStore.bundledMapping()

        XCTAssertFalse(mapping.isEmpty)
        XCTAssertEqual(mapping["764337"], ["4861.zip", "853.zip"])
        XCTAssertEqual(mapping.count, 381)
    }
}
