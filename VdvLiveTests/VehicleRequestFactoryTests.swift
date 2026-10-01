import XCTest
@testable import VdvLive

final class VehicleRequestFactoryTests: XCTestCase {
    func testTargetsThePointsEndpointOverGet() {
        let request = VehicleRequestFactory.makeRequest()

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://mapavdv.kr-vysocina.cz/Ajax/GetPoints"
        )
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testSendsTheHeadersTheFeedWasVerifiedWith() {
        let request = VehicleRequestFactory.makeRequest()

        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "*/*")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://mapavdv.kr-vysocina.cz/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), "en-US,en;q=0.7")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "User-Agent"),
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36"
        )
    }

    func testLeavesOutTheSessionCookieUntilOneIsConfigured() {
        XCTAssertNil(VehicleRequestFactory.makeRequest().value(forHTTPHeaderField: "Cookie"))
    }

    func testSendsTheSessionCookieWhenConfigured() {
        var configuration = VehicleRequestConfiguration.live
        configuration.sessionCookie = "sznlbr=1YCNil89UGEJujisjC3IaJKQ"

        let request = VehicleRequestFactory.makeRequest(configuration: configuration)

        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Cookie"),
            "sznlbr=1YCNil89UGEJujisjC3IaJKQ"
        )
    }

    func testTreatsAnEmptySessionCookieAsUnset() {
        var configuration = VehicleRequestConfiguration.live
        configuration.sessionCookie = ""

        XCTAssertNil(
            VehicleRequestFactory.makeRequest(configuration: configuration)
                .value(forHTTPHeaderField: "Cookie")
        )
    }

    func testAlwaysAsksForAFreshResponse() {
        let request = VehicleRequestFactory.makeRequest()

        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.timeoutInterval, VehicleRequestConfiguration.live.timeout)
    }

    func testBuildsTheURLFromTheConfiguredBaseURL() {
        var configuration = VehicleRequestConfiguration.live
        configuration.baseURL = URL(string: "https://example.test")!
        configuration.endpointPath = "api/points"

        let request = VehicleRequestFactory.makeRequest(configuration: configuration)

        XCTAssertEqual(request.url?.absoluteString, "https://example.test/api/points")
    }

    func testAsksForTheVehicleInfoWindow() {
        let request = VehicleRequestFactory.makeInfoWindowRequest(vehicleID: 173067)

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://mapavdv.kr-vysocina.cz/Ajax/OpenInfoWindow?id=173067"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
    }

    func testAsksForTheTimetableOfTheRun() {
        let request = VehicleRequestFactory.makeTimetableRequest(vehicleID: 173067)

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://mapavdv.kr-vysocina.cz/Ajax/GetTimetable?vehicleNumber=173067&currentStopId=0"
        )
    }
}
