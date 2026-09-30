import Foundation

/// Decodes `/Ajax/GetPoints` payloads.
///
/// The feed is produced by a third party and occasionally carries a record that
/// does not match the shape of its neighbours. Failing the whole response
/// because of one bad row would blank the map, so decoding falls back to a
/// per-record pass that keeps everything it can read and reports the rest.
struct VehiclePayloadDecoder {
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    func decode(_ data: Data) throws -> VehiclePayload {
        let decoded = try decodeRecords(data)

        var vehicles: [Vehicle] = []
        var unlocatable = 0
        vehicles.reserveCapacity(decoded.records.count)
        for record in decoded.records {
            guard let vehicle = record.makeVehicle() else {
                unlocatable += 1
                continue
            }
            vehicles.append(vehicle)
        }

        return VehiclePayload(
            vehicles: vehicles,
            skippedRecordCount: decoded.skipped,
            unlocatableRecordCount: unlocatable
        )
    }

    private func decodeRecords(_ data: Data) throws -> DecodedRecords {
        if let records = try? decoder.decode([VehicleDTO].self, from: data) {
            return DecodedRecords(records: records, skipped: 0)
        }
        return try decodeRecordsOneByOne(data)
    }

    /// Slow path: re-encode every element on its own so that one unreadable
    /// record cannot take the rest of the response down with it.
    private func decodeRecordsOneByOne(_ data: Data) throws -> DecodedRecords {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw VehicleAPIError.malformedPayload("The body was not valid JSON.")
        }
        guard let elements = object as? [Any] else {
            throw VehicleAPIError.malformedPayload("Expected a JSON array of vehicle records.")
        }

        var records: [VehicleDTO] = []
        var skipped = 0
        records.reserveCapacity(elements.count)
        for element in elements {
            // `.fragmentsAllowed` is required here: without it JSONSerialization
            // raises an Objective-C exception for a top level scalar such as a
            // bare number in the array, and `try?` cannot catch those.
            guard
                let elementData = try? JSONSerialization.data(
                    withJSONObject: element,
                    options: [.fragmentsAllowed]
                ),
                let record = try? decoder.decode(VehicleDTO.self, from: elementData)
            else {
                skipped += 1
                continue
            }
            records.append(record)
        }
        return DecodedRecords(records: records, skipped: skipped)
    }

    private struct DecodedRecords {
        let records: [VehicleDTO]
        let skipped: Int
    }
}
