import Foundation

/// Errors surfaced by ``VehicleAPIClient``.
///
/// Messages are written to be shown to a user, since the map has nothing else
/// to explain why it is empty.
enum VehicleAPIError: Error, Equatable, LocalizedError {
    /// The request never made it to the server, e.g. the device is offline.
    case transport(String)
    /// The server answered with a status code outside `200..<300`.
    case httpStatus(Int)
    /// The response body was not the JSON array of vehicle records.
    case malformedPayload(String)

    var errorDescription: String? {
        switch self {
        case .transport(let description):
            return description
        case .httpStatus(let statusCode):
            return String(format: String(localized: "The map server answered with HTTP %lld."), statusCode)
        case .malformedPayload(let description):
            return String(
                format: String(localized: "The map server sent an unexpected response. %@"),
                description
            )
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .transport:
            return String(localized: "Check your connection and try again.")
        case .httpStatus, .malformedPayload:
            return String(localized: "Try again in a moment.")
        }
    }
}
