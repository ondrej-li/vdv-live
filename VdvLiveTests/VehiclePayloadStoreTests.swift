import XCTest
@testable import VdvLive

/// The last payload, kept on disk for a launch with no network.
final class VehiclePayloadStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("payload-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var payload: VehiclePayload {
        VehiclePayload(
            vehicles: [
                Fixture.vehicle(id: 1, latitude: 49.3960, longitude: 15.5910),
                Fixture.vehicle(
                    id: 2,
                    latitude: 49.6070,
                    longitude: 15.5810,
                    delay: .minutes(3),
                    traction: .train
                )
            ],
            skippedRecordCount: 4,
            unlocatableRecordCount: 2
        )
    }

    func testKeepsThePayloadAndWhenItWasFetched() {
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        VehiclePayloadFiles(directory: directory).save(payload, fetchedAt: fetchedAt)

        let stored = VehiclePayloadFiles(directory: directory).load()

        XCTAssertEqual(stored?.fetchedAt, fetchedAt)
        XCTAssertEqual(stored?.payload, payload)
    }

    func testSaysNothingWhenNothingWasKept() {
        XCTAssertNil(VehiclePayloadFiles(directory: directory).load())
    }

    func testIgnoresAFileItCannotRead() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a payload".utf8)
            .write(to: directory.appendingPathComponent("last-payload.json"))

        XCTAssertNil(VehiclePayloadFiles(directory: directory).load())
    }

    func testKeepsEveryFieldOfAVehicle() throws {
        VehiclePayloadFiles(directory: directory).save(
            payload,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let stored = try XCTUnwrap(VehiclePayloadFiles(directory: directory).load())
        let bus = try XCTUnwrap(stored.payload.vehicles.first)
        let train = stored.payload.vehicles[1]

        XCTAssertEqual(bus.id, 1)
        XCTAssertEqual(bus.line, "841334")
        XCTAssertEqual(bus.latitude, 49.3960)
        XCTAssertEqual(bus.longitude, 15.5910)
        XCTAssertEqual(bus.destination, "Jihlava,aut.nádr.")
        XCTAssertEqual(bus.delay, .minutes(0))
        XCTAssertEqual(bus.traction, .bus)
        XCTAssertEqual(train.delay, .minutes(3))
        XCTAssertEqual(train.traction, .train)
        XCTAssertEqual(stored.payload.skippedRecordCount, 4)
        XCTAssertEqual(stored.payload.unlocatableRecordCount, 2)
    }
}
