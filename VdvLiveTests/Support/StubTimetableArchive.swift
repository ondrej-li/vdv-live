import Foundation
@testable import VdvLive

/// Archive reader that answers from a fixture instead of the network, so the
/// timetable store can be tested without downloading anything.
struct StubTimetableArchive: TimetableArchiveReading {
    let archive: Data
    /// Entry names that should fail, or `*` for everything.
    var failures: Set<String> = []
    /// What the server offers when asked which archive it has.
    var serverVersion = ArchiveVersion(
        etag: "\"a3306dce1451dd1:0\"",
        lastModified: Date(timeIntervalSince1970: 1_700_000_000),
        size: 106_230_086
    )
    /// True when the server cannot be asked at all, while the index still reads.
    var versionFails = false

    func entries() async throws -> [ZipArchive.Entry] {
        if failures.contains("*") { throw TimetableError.transport("offline") }
        return try ZipArchive.entries(in: archive)
    }

    func contents(of entry: ZipArchive.Entry) async throws -> Data {
        if failures.contains(entry.name) || failures.contains("*") {
            throw TimetableError.transport("offline")
        }
        return try ZipArchive.contents(of: entry, in: archive)
    }

    func version() async throws -> ArchiveVersion {
        if versionFails || failures.contains("*") {
            throw TimetableError.transport("offline")
        }
        return serverVersion
    }
}

extension StubTimetableArchive {
    /// The archive sample checked in with the tests: one entry, for line 764337.
    static func fromFixture() throws -> StubTimetableArchive {
        let url = try XCTUnwrapFixture("jdf-archive-sample")
        return StubTimetableArchive(archive: try Data(contentsOf: url))
    }
}

private func XCTUnwrapFixture(_ name: String) throws -> URL {
    let bundle = Bundle(for: StubTimetableArchiveBundleMarker.self)
    guard let url = bundle.url(forResource: name, withExtension: "zip") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return url
}

private final class StubTimetableArchiveBundleMarker {}
