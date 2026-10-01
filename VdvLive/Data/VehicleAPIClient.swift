import Foundation
import OSLog

/// Talks to the Vysočina regional map feed.
struct VehicleAPIClient: VehicleFetching {
    private static let logger = Logger(subsystem: "cz.ondralinek.VdvLive", category: "vehicle-feed")

    let configuration: VehicleRequestConfiguration
    private let session: URLSession
    private let payloadDecoder: VehiclePayloadDecoder

    init(
        configuration: VehicleRequestConfiguration = .live,
        session: URLSession = .shared,
        payloadDecoder: VehiclePayloadDecoder = VehiclePayloadDecoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.payloadDecoder = payloadDecoder
    }

    func fetchVehicles() async throws -> VehiclePayload {
        let request = VehicleRequestFactory.makeRequest(configuration: configuration)
        do {
            let (data, response) = try await session.data(for: request)
            let payload = try validate(data: data, response: response)
            Self.logger.debug(
                "Fetched \(payload.vehicles.count, privacy: .public) vehicles, skipped \(payload.skippedRecordCount, privacy: .public) unreadable and \(payload.unlocatableRecordCount, privacy: .public) unlocatable records."
            )
            return payload
        } catch let error as VehicleAPIError {
            throw error
        } catch {
            let message = Self.describe(error)
            Self.logger.error("Vehicle feed request failed: \(message, privacy: .public)")
            throw VehicleAPIError.transport(message)
        }
    }

    private func validate(data: Data, response: URLResponse) throws -> VehiclePayload {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VehicleAPIError.malformedPayload("The response was not an HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw VehicleAPIError.httpStatus(httpResponse.statusCode)
        }
        guard !data.isEmpty else {
            throw VehicleAPIError.malformedPayload("The body was empty.")
        }
        return try payloadDecoder.decode(data)
    }

    private static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else {
            return error.localizedDescription
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return String(localized: "There is no internet connection.")
        case .timedOut:
            return String(localized: "The map server did not respond in time.")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return String(localized: "The map server could not be reached.")
        default:
            return urlError.localizedDescription
        }
    }
}
