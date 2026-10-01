import XCTest
@testable import VdvLive

/// Fixtures are real bytes from the official archive: the tiny outer archive
/// holds the entry for line 764337 exactly as the national archive does.
final class ZipArchiveTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "zip"),
            "No \(name).zip in the test bundle"
        )
        return try Data(contentsOf: url)
    }

    func testReadsTheCentralDirectory() throws {
        let archive = try fixture("jdf-archive-sample")

        let entries = try ZipArchive.entries(in: archive)

        XCTAssertEqual(entries.map(\.name), ["853.zip"])
        let entry = try XCTUnwrap(entries.first)
        // The sample was written with `zip`, which stores an already compressed
        // entry rather than deflating it again. Both methods are exercised here:
        // this one is stored, the files inside it are deflated.
        XCTAssertEqual(entry.method, 0)
        XCTAssertEqual(entry.compressedSize, 4623)
        XCTAssertEqual(entry.uncompressedSize, 4623)
        XCTAssertEqual(entry.localHeaderOffset, 0)
    }

    func testReadsTheDirectoryFromTheEndOfTheFileAlone() throws {
        let archive = try fixture("jdf-archive-sample")
        // A range request only ever brings back the tail, so this is the shape
        // the app really works with.
        let tail = archive.suffix(1200)

        let entries = try ZipArchive.entries(inTail: Data(tail), archiveSize: archive.count)

        XCTAssertEqual(entries.map(\.name), ["853.zip"])
    }

    func testRefusesATailThatMissesTheDirectory() throws {
        let archive = try fixture("jdf-archive-sample")

        XCTAssertThrowsError(
            try ZipArchive.entries(inTail: archive.prefix(200), archiveSize: archive.count)
        ) { error in
            XCTAssertEqual(error as? ZipArchive.Failure, .notAZip)
        }
    }

    func testExtractsAnEntry() throws {
        let archive = try fixture("jdf-archive-sample")
        let entry = try XCTUnwrap(try ZipArchive.entries(in: archive).first)

        let inner = try ZipArchive.contents(of: entry, in: archive)

        // What comes out is the line's own zip, which has to be readable too.
        // Not every line carries every file: this one has no LinExt.txt.
        let innerEntries = try ZipArchive.entries(in: inner)
        XCTAssertEqual(
            innerEntries.map(\.name).sorted(),
            [
                "Caskody.txt", "Dopravci.txt", "Linky.txt", "Navaznosti.txt", "Pevnykod.txt",
                "Spoje.txt", "Udaje.txt", "VerzeJDF.txt", "Zaslinky.txt", "Zasspoje.txt",
                "Zastavky.txt"
            ]
        )
    }

    func testReadsTheLineFileOfTheExtractedEntry() throws {
        let archive = try fixture("jdf-archive-sample")
        let outerEntry = try XCTUnwrap(try ZipArchive.entries(in: archive).first)
        let inner = try ZipArchive.contents(of: outerEntry, in: archive)

        let innerEntries = try ZipArchive.entries(in: inner)
        let linky = try XCTUnwrap(innerEntries.first { $0.name == "Linky.txt" })
        XCTAssertEqual(linky.method, 8)
        let bytes = try ZipArchive.contents(of: linky, in: inner)

        // CP1250, which is what the archive uses.
        let text = try XCTUnwrap(String(data: bytes, encoding: .windowsCP1250))
        XCTAssertTrue(text.contains("\"764337\""), text)
        XCTAssertTrue(text.contains("Třešť-Brtnice"), text)
    }

    func testReportsAMissingEntryByName() throws {
        let archive = try fixture("jdf-archive-sample")
        let entries = try ZipArchive.entries(in: archive)

        XCTAssertNil(entries.first { $0.name == "999999.zip" })
    }

    func testRefusesBytesThatAreNotAnEntry() throws {
        let archive = try fixture("jdf-archive-sample")
        let entry = try XCTUnwrap(try ZipArchive.entries(in: archive).first)

        XCTAssertThrowsError(try ZipArchive.contents(of: entry, in: Data("nope".utf8))) { error in
            XCTAssertEqual(error as? ZipArchive.Failure, .damagedEntry("853.zip"))
        }
    }

    func testRejectsBytesThatAreNotAnArchive() {
        XCTAssertThrowsError(try ZipArchive.entries(in: Data("not a zip".utf8))) { error in
            XCTAssertEqual(error as? ZipArchive.Failure, .notAZip)
        }
    }
}
