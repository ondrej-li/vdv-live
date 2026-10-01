import Foundation
import XCTest
@testable import VdvLive

/// The archive's own HTTP layer: what the app asks the portal for, and what it
/// makes of the answer.
final class TimetableArchiveClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func makeClient() -> HTTPTimetableArchive {
        HTTPTimetableArchive(session: URLProtocolStub.makeSession())
    }

    private func respond(statusCode: Int, headers: [String: String], body: Data = Data()) {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? TimetableArchive.address,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
            guard let response else { throw URLError(.badServerResponse) }
            return (response, body)
        }
    }

    func testAsksForASingleByteAndReadsTheVersionOutOfTheAnswer() async throws {
        respond(
            statusCode: 206,
            headers: [
                "Content-Range": "bytes 0-0/106230086",
                "ETag": "\"a3306dce1451dd1:0\"",
                "Last-Modified": "Wed, 30 Sep 2026 19:49:29 GMT"
            ],
            body: Data([0x50])
        )

        let version = try await makeClient().version()

        XCTAssertEqual(URLProtocolStub.lastRequest?.value(forHTTPHeaderField: "Range"), "bytes=0-0")
        XCTAssertEqual(version.etag, "\"a3306dce1451dd1:0\"")
        XCTAssertEqual(version.size, 106_230_086)

        // The date is parsed in its own right: a formatter that quietly produced
        // nil, or a date off by a time zone, would make every check say "newer".
        let published = try XCTUnwrap(version.lastModified)
        let parts = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(secondsFromGMT: 0)!,
            from: published
        )
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 9)
        XCTAssertEqual(parts.day, 30)
        XCTAssertEqual(parts.hour, 19)
        XCTAssertEqual(parts.minute, 49)
        XCTAssertEqual(parts.second, 29)
    }

    func testAServerWithoutADateOrAnEtagIsStillAnswered() async throws {
        respond(statusCode: 206, headers: ["Content-Range": "bytes 0-0/4096"])

        let version = try await makeClient().version()

        XCTAssertNil(version.etag)
        XCTAssertNil(version.lastModified)
        XCTAssertEqual(version.size, 4_096)
    }

    func testRefusesAServerThatIgnoresTheRange() async {
        // A 200 means the whole 106 MB archive was on its way.
        respond(statusCode: 200, headers: ["Content-Length": "106230086"])

        do {
            _ = try await makeClient().version()
            XCTFail("Expected the whole-file answer to be refused")
        } catch {
            XCTAssertEqual(error as? TimetableError, .rangeNotSupported)
        }
    }

    func testReportsAnUnrecognisedAnswer() async {
        respond(statusCode: 503, headers: [:])

        do {
            _ = try await makeClient().version()
            XCTFail("Expected the answer to be refused")
        } catch {
            XCTAssertEqual(error as? TimetableError, .unrecognisedResponse)
        }
    }

    func testReportsATransportFailureAsSuch() async {
        URLProtocolStub.handler = { _ in throw URLError(.notConnectedToInternet) }

        do {
            _ = try await makeClient().version()
            XCTFail("Expected the request to fail")
        } catch let error as TimetableError {
            guard case .transport = error else { return XCTFail("\(error)") }
        } catch {
            XCTFail("\(error)")
        }
    }

    // MARK: - Comparing two publications

    func testTheEtagDecidesWhenBothHaveOne() {
        let first = ArchiveVersion(etag: "a", lastModified: nil, size: 1)

        XCTAssertTrue(first.describesSamePublication(as: ArchiveVersion(etag: "a", lastModified: nil, size: 9)))
        XCTAssertFalse(first.describesSamePublication(as: ArchiveVersion(etag: "b", lastModified: nil, size: 1)))
    }

    func testTheDateDecidesWhenTheEtagIsMissing() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = ArchiveVersion(etag: nil, lastModified: date, size: 1)

        XCTAssertTrue(first.describesSamePublication(as: ArchiveVersion(etag: nil, lastModified: date, size: 9)))
        XCTAssertFalse(
            first.describesSamePublication(
                as: ArchiveVersion(etag: nil, lastModified: date.addingTimeInterval(60), size: 1)
            )
        )
    }

    func testTheSizeIsAllThereIsWhenNothingElseIsOffered() {
        let first = ArchiveVersion(etag: nil, lastModified: nil, size: 4_096)

        XCTAssertTrue(first.describesSamePublication(as: ArchiveVersion(etag: nil, lastModified: nil, size: 4_096)))
        XCTAssertFalse(first.describesSamePublication(as: ArchiveVersion(etag: nil, lastModified: nil, size: 4_097)))
    }
}
