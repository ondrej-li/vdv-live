import XCTest
@testable import VdvMap

final class VehiclePayloadDecoderTests: XCTestCase {
    private let decoder = VehiclePayloadDecoder()

    private func decode(_ payload: String) throws -> VehiclePayload {
        try decoder.decode(Data(payload.utf8))
    }

    func testDecodesEveryWellFormedRecord() throws {
        let payload = try decode(SamplePoints.valid)

        XCTAssertEqual(payload.skippedRecordCount, 0)
        XCTAssertEqual(payload.unlocatableRecordCount, 1)
        XCTAssertEqual(payload.vehicles.count, 5)
    }

    func testMapsFeedFieldsOntoTheDomainModel() throws {
        let payload = try decode(SamplePoints.valid)
        let vehicle = try XCTUnwrap(payload.vehicles.first { $0.id == 172923 })

        XCTAssertEqual(vehicle.line, "841334")
        XCTAssertEqual(vehicle.latitude, 49.39595413208008, accuracy: 0.0000001)
        XCTAssertEqual(vehicle.longitude, 16.366287231445312, accuracy: 0.0000001)
        XCTAssertEqual(vehicle.destination, "Bystřice n.Pern.,aut.nádr.")
        XCTAssertEqual(vehicle.delay, .minutes(5))
        XCTAssertEqual(vehicle.traction, .bus)
    }

    func testReadsNegativeIdsUsedByTrains() throws {
        let payload = try decode(SamplePoints.valid)
        let train = try XCTUnwrap(payload.vehicles.first { $0.id == -2435 })

        XCTAssertEqual(train.traction, .train)
        XCTAssertEqual(train.line, "5907")
    }

    func testTreatsMissingDelaySentinelAsUnknown() throws {
        let payload = try decode(SamplePoints.valid)
        let vehicle = try XCTUnwrap(payload.vehicles.first { $0.id == 173939 })

        XCTAssertEqual(vehicle.delay, .unknown)
        XCTAssertNil(vehicle.delay.minutes)
    }

    func testTreatsDestinationPlaceholderAsMissing() throws {
        let payload = try decode(SamplePoints.valid)

        let train = try XCTUnwrap(payload.vehicles.first { $0.id == -2435 })
        XCTAssertNil(train.destination)

        let unknown = try XCTUnwrap(payload.vehicles.first { $0.id == 173669 })
        XCTAssertNil(unknown.destination)
    }

    func testDropsVehiclesThatReportNoPosition() throws {
        let payload = try decode(SamplePoints.valid)

        XCTAssertEqual(payload.unlocatableRecordCount, 1)
        XCTAssertFalse(payload.vehicles.contains { $0.id == 173861 })
    }

    func testMapsUnrecognisedTractionOntoUnknown() throws {
        let payload = try decode(SamplePoints.valid)
        let vehicle = try XCTUnwrap(payload.vehicles.first { $0.id == 173875 })

        XCTAssertEqual(vehicle.traction, .unknown)
    }

    func testKeepsReadableRecordsWhenSomeAreMalformed() throws {
        let payload = try decode(SamplePoints.partiallyMalformed)

        XCTAssertEqual(payload.skippedRecordCount, 3)
        XCTAssertEqual(payload.vehicles.count, 2)
        XCTAssertEqual(Set(payload.vehicles.map(\.id)), [1, 5])
    }

    func testSkipsNullRecords() throws {
        let payload = try decode(SamplePoints.withNullRecord)

        XCTAssertEqual(payload.skippedRecordCount, 1)
        XCTAssertEqual(payload.vehicles.map(\.id), [1])
    }

    func testDecodesEmptyArray() throws {
        let payload = try decode(SamplePoints.emptyArray)

        XCTAssertEqual(payload.vehicles.count, 0)
        XCTAssertEqual(payload.skippedRecordCount, 0)
    }

    func testRejectsPayloadThatIsNotAnArray() throws {
        XCTAssertThrowsError(try decode(SamplePoints.notAnArray)) { error in
            XCTAssertEqual(
                error as? VehicleAPIError,
                .malformedPayload("Expected a JSON array of vehicle records.")
            )
        }
    }

    func testRejectsBodyThatIsNotJSON() throws {
        XCTAssertThrowsError(try decode(SamplePoints.notJSON)) { error in
            XCTAssertEqual(
                error as? VehicleAPIError,
                .malformedPayload("The body was not valid JSON.")
            )
        }
    }
}
