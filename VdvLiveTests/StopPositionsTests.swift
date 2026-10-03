import Foundation
import XCTest
@testable import VdvLive

final class StopPositionsTests: XCTestCase {
    private let row = #"""
    {"name":"Okříšky,aut.nádr.","latitude":49.2455,"longitude":15.76811,
     "match":"osm-name","accuracyMetres":40.0}
    """#

    func testDecodesARowFromTheShippedFile() throws {
        let position = try JSONDecoder().decode(StopPosition.self, from: Data(row.utf8))

        XCTAssertEqual(position.name, "Okříšky,aut.nádr.")
        XCTAssertEqual(position.latitude, 49.2455, accuracy: 0.00001)
        XCTAssertEqual(position.longitude, 15.76811, accuracy: 0.00001)
        XCTAssertEqual(position.match, .name)
        XCTAssertEqual(position.accuracyMetres, 40, accuracy: 0.001)
        XCTAssertTrue(position.isExact)
    }

    func testReadsEveryMatchKindTheGeneratorCanWrite() throws {
        for (kind, expected) in [("osm-name", StopPosition.Match.name),
                                 ("osm-village", .village),
                                 ("osm-near", .near),
                                 ("place", .place)] {
            let json = #"{"name":"X","latitude":49.0,"longitude":15.0,"match":"\#(kind)","accuracyMetres":600}"#
            let position = try JSONDecoder().decode(StopPosition.self, from: Data(json.utf8))
            XCTAssertEqual(position.match, expected)
        }
    }

    /// A village centre is not a stop's position, so the app has to be able to tell.
    func testAVillageCentreIsNotAnExactPosition() throws {
        let json = #"{"name":"X","latitude":49.0,"longitude":15.0,"match":"place","accuracyMetres":600}"#
        let position = try JSONDecoder().decode(StopPosition.self, from: Data(json.utf8))

        XCTAssertFalse(position.isExact)
    }

    func testFoldsANameTheSameWayTheFileIsKeyed() {
        // The keys in the file carry no diacritics, spaces or punctuation, because the
        // generator and this have to agree without either knowing about the other.
        XCTAssertEqual(StopPositions.lookupKey(for: "Okříšky,aut.nádr."), "okriskyautnadr")
        XCTAssertEqual(StopPositions.lookupKey(for: "Okrisky, aut. nadr."), "okriskyautnadr")
        XCTAssertEqual(StopPositions.lookupKey(for: "Žďár n.Sáz.,Strojírenská ŽĎAS"),
                       "zdarnsazstrojirenskazdas")
        XCTAssertEqual(StopPositions.lookupKey(for: "  Brtnice,nám.  "), "brtnicenam")
    }

    func testFindsABundledStopByTheNameTheTimetableShows() {
        let positions = StopPositions.bundled()

        XCTAssertGreaterThan(positions.count, 1_000)
        let position = positions.position(forStopNamed: "Brtnice,nám.")
        XCTAssertNotNil(position)
        XCTAssertEqual(position?.match, .name)
        // Brtnice is a village in the Jihlava district; the position has to be there and
        // nowhere else, which is the whole point of the guards in the generator.
        XCTAssertEqual(position?.latitude ?? 0, 49.3073, accuracy: 0.05)
        XCTAssertEqual(position?.longitude ?? 0, 15.6767, accuracy: 0.05)
    }

    func testAnUnknownStopHasNoPosition() {
        XCTAssertNil(StopPositions.bundled().position(forStopNamed: "Nikde,nic"))
        XCTAssertNil(StopPositions.empty.position(forStopNamed: "Brtnice,nám."))
    }

    /// What the map layer asks for: whatever is inside the viewport, in a stable
    /// order so the flags are drawn the same way every time.
    func testFindsTheStopsInsideARectangle() {
        let positions = StopPositions.bundled()
        let around = positions.positions(latitude: 49.297...49.317,
                                        longitude: 15.666...15.687)

        XCTAssertTrue(around.contains { $0.name == "Brtnice,nám." })
        // Třešť is the next town along, well outside a 2 km box round Brtnice.
        XCTAssertFalse(around.contains { $0.name == "Třešť,nám." })
        XCTAssertEqual(around, around.sorted { $0.name < $1.name })
        XCTAssertTrue(around.allSatisfy(\.isExact))
    }

    func testAnEmptyRectangleHasNoStops() {
        XCTAssertTrue(StopPositions.bundled()
            .positions(latitude: 0...0.001, longitude: 0...0.001).isEmpty)
    }
}
