import Foundation

/// Wire format of one element of `/Ajax/GetPoints`.
///
/// The feed is not snake case and uses short field names; the mapping to the
/// names the rest of the app uses lives in ``CodingKeys``.
struct VehicleDTO: Decodable, Equatable {
    let id: Int
    let latitude: Double
    let longitude: Double
    let line: String
    let delay: Int
    let destination: String
    let traction: String

    enum CodingKeys: String, CodingKey {
        case id
        case latitude = "lat"
        case longitude = "lng"
        case line = "text"
        case delay
        case destination = "finalStopName"
        case traction
    }
}

extension VehicleDTO {
    /// Suffix the feed uses when it has no destination, e.g. `-1 N/a`.
    static let destinationPlaceholderSuffix = "N/a"

    /// Maps the wire record onto the domain model, `nil` when the record has no
    /// usable position.
    func makeVehicle() -> Vehicle? {
        let vehicle = Vehicle(
            id: id,
            line: line,
            latitude: latitude,
            longitude: longitude,
            destination: Self.normalizedDestination(destination),
            delay: VehicleDelay(rawMinutes: delay),
            traction: Traction(serverValue: traction)
        )
        return vehicle.isLocatable ? vehicle : nil
    }

    /// Turns the placeholders the feed sends for "no destination" into `nil`.
    static func normalizedDestination(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasSuffix(destinationPlaceholderSuffix) else {
            return nil
        }
        return trimmed
    }
}
