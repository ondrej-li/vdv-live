import Foundation
import XCTest
@testable import VdvLive

final class VehicleDetailHTMLParserTests: XCTestCase {
    func testReadsTheInfoWindowTable() throws {
        let info = try VehicleDetailHTMLParser.parseInfoWindow(SampleDetailHTML.infoWindow)

        XCTAssertEqual(info.line, "764931")
        XCTAssertEqual(info.serviceNumber, "11")
        XCTAssertEqual(info.stopName, "Telč,Hradecká škola")
        XCTAssertEqual(info.reportedDelayMinutes, 0)
        XCTAssertEqual(info.isBarrierFree, false)
    }

    func testReadsATickedBarrierFreeCheckboxAndNegativeDelay() throws {
        let info = try VehicleDetailHTMLParser.parseInfoWindow(
            SampleDetailHTML.infoWindowBarrierFreeAndLate
        )

        XCTAssertEqual(info.line, "841334")
        XCTAssertEqual(info.serviceNumber, "9")
        XCTAssertEqual(info.isBarrierFree, true)
        XCTAssertEqual(info.reportedDelayMinutes, -3)
    }

    func testReadsNoDelayWhenTheFeedSendsItsSentinel() throws {
        let info = try VehicleDetailHTMLParser.parseInfoWindow(
            SampleDetailHTML.infoWindowWithoutADelay
        )

        XCTAssertNil(info.reportedDelayMinutes)
    }

    func testReadsTheStopsOfTheRun() throws {
        let stops = try VehicleDetailHTMLParser.parseRunStops(SampleDetailHTML.timetable)

        XCTAssertEqual(
            stops.map(\.name),
            ["Telč,aut.nádr.", "Telč,Hradecká škola", "Hostětice", "Hostětice,Částkovice", "Mrákotín"]
        )
        XCTAssertEqual(stops.first?.arrival, "14:06")
        XCTAssertEqual(stops.first?.departure, "14:06")
        XCTAssertEqual(stops.first?.timeText, "14:06")
        XCTAssertEqual(stops.last?.timeText, "14:21")
    }

    func testLeavesOutTimesTheTimetableDoesNotHave() throws {
        let stops = try VehicleDetailHTMLParser.parseRunStops(
            SampleDetailHTML.timetableWithEmptyTimes
        )

        XCTAssertEqual(stops.map(\.name), ["Jihlava,aut.nádr.", "Jihlava,ZOO"])
        XCTAssertNil(stops.first?.timeText)
        XCTAssertEqual(stops.last?.timeText, "10:15")
    }

    func testDerivesTheStopAndTheOneAfterIt() throws {
        let detail = try makeDetail()

        XCTAssertEqual(detail.lineNumber, "931")
        XCTAssertEqual(detail.serviceNumber, "11")
        XCTAssertEqual(detail.stop?.name, "Telč,Hradecká škola")
        XCTAssertEqual(detail.stop?.timeText, "14:12")
        XCTAssertEqual(detail.nextStop?.name, "Hostětice")
        XCTAssertEqual(detail.nextStop?.timeText, "14:16")
    }

    func testHasNoNextStopAtTheEndOfTheRun() throws {
        let info = try VehicleDetailHTMLParser.parseInfoWindow(SampleDetailHTML.infoWindow)
        let stops = try VehicleDetailHTMLParser.parseRunStops(SampleDetailHTML.timetable)
        let detail = VehicleDetail(
            lineCode: LineCode(raw: info.line ?? ""),
            serviceNumber: info.serviceNumber,
            isBarrierFree: info.isBarrierFree,
            stopName: stops.last?.name,
            reportedDelayMinutes: info.reportedDelayMinutes,
            runStops: stops
        )

        XCTAssertEqual(detail.stop?.name, "Mrákotín")
        XCTAssertNil(detail.nextStop)
    }

    func testHasNoStopsWhenTheReportedStopIsNotInTheRun() throws {
        let info = try VehicleDetailHTMLParser.parseInfoWindow(SampleDetailHTML.infoWindow)
        let detail = VehicleDetail(
            lineCode: LineCode(raw: info.line ?? ""),
            serviceNumber: info.serviceNumber,
            isBarrierFree: info.isBarrierFree,
            stopName: "Někde jinde",
            reportedDelayMinutes: info.reportedDelayMinutes,
            runStops: [RunStop(name: "Jiná zastávka", arrival: "10:00", departure: "10:00")]
        )

        XCTAssertNil(detail.stop)
        XCTAssertNil(detail.nextStop)
    }

    func testIgnoresRowsItDoesNotKnow() throws {
        let html = #"""
        <table><tbody>
            <tr><th>Linka</th><td>764931</td></tr>
            <tr><th>Něco nového</th><td>cokoliv</td></tr>
        </tbody></table>
        """#

        let info = try VehicleDetailHTMLParser.parseInfoWindow(html)

        XCTAssertEqual(info.line, "764931")
        XCTAssertNil(info.serviceNumber)
        XCTAssertNil(info.stopName)
    }

    private func makeDetail() throws -> VehicleDetail {
        let info = try VehicleDetailHTMLParser.parseInfoWindow(SampleDetailHTML.infoWindow)
        let stops = try VehicleDetailHTMLParser.parseRunStops(SampleDetailHTML.timetable)
        return VehicleDetail(
            lineCode: LineCode(raw: info.line ?? ""),
            serviceNumber: info.serviceNumber,
            isBarrierFree: info.isBarrierFree,
            stopName: info.stopName,
            reportedDelayMinutes: info.reportedDelayMinutes,
            runStops: stops
        )
    }
}

final class VehicleDetailClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func makeClient() -> VehicleDetailClient {
        VehicleDetailClient(session: URLProtocolStub.makeSession())
    }

    private func stub(pages: [String: String], failing: Set<String> = []) {
        URLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            guard let url = request.url, let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            ) else {
                throw URLError(.badURL)
            }
            if failing.contains(path) {
                throw URLError(.cannotConnectToHost)
            }
            return (response, Data((pages[path] ?? "").utf8))
        }
    }

    func testCombinesTheInfoWindowWithTheTimetable() async throws {
        stub(pages: [
            "/Ajax/OpenInfoWindow": SampleDetailHTML.infoWindow,
            "/Ajax/GetTimetable": SampleDetailHTML.timetable
        ])

        let detail = try await makeClient().fetchDetail(for: Fixture.vehicle(id: 173067, line: "764931"))

        XCTAssertEqual(detail.lineNumber, "931")
        XCTAssertEqual(detail.serviceNumber, "11")
        XCTAssertEqual(detail.stop?.name, "Telč,Hradecká škola")
        XCTAssertEqual(detail.nextStop?.name, "Hostětice")
        XCTAssertEqual(detail.runStops.count, 5)
    }

    func testStillDescribesTheVehicleWhenTheTimetableFails() async throws {
        stub(
            pages: ["/Ajax/OpenInfoWindow": SampleDetailHTML.infoWindow],
            failing: ["/Ajax/GetTimetable"]
        )

        let detail = try await makeClient().fetchDetail(for: Fixture.vehicle(id: 173067, line: "764931"))

        XCTAssertEqual(detail.serviceNumber, "11")
        XCTAssertEqual(detail.stopName, "Telč,Hradecká škola")
        XCTAssertTrue(detail.runStops.isEmpty)
        XCTAssertNil(detail.stop)
    }

    func testFallsBackToTheFeedLineWhenTheInfoWindowHasNone() async throws {
        stub(pages: [
            "/Ajax/OpenInfoWindow": "<table><tbody></tbody></table>",
            "/Ajax/GetTimetable": SampleDetailHTML.timetable
        ])

        let detail = try await makeClient().fetchDetail(for: Fixture.vehicle(id: 1, line: "764337"))

        XCTAssertEqual(detail.lineNumber, "337")
    }

    func testThrowsWhenTheInfoWindowFails() async {
        stub(pages: [:], failing: ["/Ajax/OpenInfoWindow"])

        do {
            _ = try await makeClient().fetchDetail(for: Fixture.vehicle(id: 1))
            XCTFail("Expected the request to fail")
        } catch {
            XCTAssertNotNil(error as? VehicleAPIError)
        }
    }

    /// The timetable endpoint resolves the run itself and will happily answer
    /// with a different one. Stops that belong to another vehicle would produce a
    /// confidently wrong next stop, so they are dropped instead.
    func testIgnoresATimetableForADifferentLine() async throws {
        stub(pages: [
            "/Ajax/OpenInfoWindow": SampleDetailHTML.infoWindow,
            "/Ajax/GetTimetable": SampleDetailHTML.timetable.replacingOccurrences(
                of: "<span>764931 / 11</span>",
                with: "<span>764337 / 11</span>"
            )
        ])

        let detail = try await makeClient().fetchDetail(for: Fixture.vehicle(id: 173067, line: "764931"))

        XCTAssertEqual(detail.lineNumber, "931")
        XCTAssertEqual(detail.stopName, "Telč,Hradecká škola")
        XCTAssertTrue(detail.runStops.isEmpty)
        XCTAssertNil(detail.nextStop)
    }

    func testIgnoresATimetableForADifferentServiceNumber() async throws {
        stub(pages: [
            "/Ajax/OpenInfoWindow": SampleDetailHTML.infoWindow,
            "/Ajax/GetTimetable": SampleDetailHTML.timetable.replacingOccurrences(
                of: "<span>764931 / 11</span>",
                with: "<span>764931 / 12</span>"
            )
        ])

        let detail = try await makeClient().fetchDetail(for: Fixture.vehicle(id: 173067, line: "764931"))

        XCTAssertEqual(detail.serviceNumber, "11")
        XCTAssertTrue(detail.runStops.isEmpty)
        XCTAssertNil(detail.nextStop)
    }

    func testIgnoresAnUnlabelledTimetable() async throws {
        // Without the run label there is no way to tell which vehicle the stops
        // belong to. Dropping them costs the next stop; keeping them could show
        // the next stop of a completely different bus.
        stub(pages: [
            "/Ajax/OpenInfoWindow": SampleDetailHTML.infoWindow,
            "/Ajax/GetTimetable": SampleDetailHTML.timetable.replacingOccurrences(
                of: "<span>764931 / 11</span>",
                with: "<span>-- / --</span>"
            )
        ])

        let detail = try await makeClient().fetchDetail(for: Fixture.vehicle(id: 173067, line: "764931"))

        XCTAssertTrue(detail.runStops.isEmpty)
        XCTAssertNil(detail.stop)
        XCTAssertNil(detail.nextStop)
    }
}
