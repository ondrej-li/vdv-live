import Foundation
import XCTest
@testable import VdvLive

final class VehicleAPIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func makeClient() -> VehicleAPIClient {
        VehicleAPIClient(session: URLProtocolStub.makeSession())
    }

    func testDecodesASuccessfulResponse() async throws {
        URLProtocolStub.respond(statusCode: 200, body: Data(SamplePoints.valid.utf8))

        let payload = try await makeClient().fetchVehicles()

        XCTAssertEqual(payload.vehicles.count, 5)
        XCTAssertEqual(payload.unlocatableRecordCount, 1)
    }

    func testSendsTheHeadersTheFeedExpects() async throws {
        URLProtocolStub.respond(statusCode: 200, body: Data(SamplePoints.valid.utf8))

        _ = try await makeClient().fetchVehicles()

        XCTAssertEqual(
            URLProtocolStub.lastRequest?.value(forHTTPHeaderField: "X-Requested-With"),
            "XMLHttpRequest"
        )
        XCTAssertEqual(URLProtocolStub.lastRequest?.httpMethod, "GET")
    }

    func testReportsTheStatusCodeWhenTheServerFails() async {
        URLProtocolStub.respond(statusCode: 503, body: Data())

        do {
            _ = try await makeClient().fetchVehicles()
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertEqual(error as? VehicleAPIError, .httpStatus(503))
        }
    }

    func testReportsAnEmptyBody() async {
        URLProtocolStub.respond(statusCode: 200, body: Data())

        do {
            _ = try await makeClient().fetchVehicles()
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertEqual(error as? VehicleAPIError, .malformedPayload("The body was empty."))
        }
    }

    func testReportsABodyThatIsNotTheExpectedJSON() async {
        URLProtocolStub.respond(statusCode: 200, body: Data(SamplePoints.notJSON.utf8))

        do {
            _ = try await makeClient().fetchVehicles()
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertEqual(
                error as? VehicleAPIError,
                .malformedPayload("The body was not valid JSON.")
            )
        }
    }

    func testTranslatesTransportFailuresIntoReadableMessages() async {
        URLProtocolStub.handler = { _ in throw URLError(.notConnectedToInternet) }

        do {
            _ = try await makeClient().fetchVehicles()
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertEqual(
                error as? VehicleAPIError,
                .transport(String(localized: "There is no internet connection."))
            )
        }
    }

    func testTranslatesTimeoutsIntoReadableMessages() async {
        URLProtocolStub.handler = { _ in throw URLError(.timedOut) }

        do {
            _ = try await makeClient().fetchVehicles()
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertEqual(
                error as? VehicleAPIError,
                .transport(String(localized: "The map server did not respond in time."))
            )
        }
    }
}
