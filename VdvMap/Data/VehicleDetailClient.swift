import Foundation
import OSLog

/// Source of the extra details the map's own popup shows.
///
/// Separate from ``VehicleFetching`` because it costs two HTTP requests per
/// call and is only worth doing for a vehicle the user actually selected.
protocol VehicleDetailFetching: Sendable {
    func fetchDetail(for vehicle: Vehicle) async throws -> VehicleDetail
}

/// Reads the detail popup and the run's timetable from the map's AJAX endpoints.
struct VehicleDetailClient: VehicleDetailFetching {
    private static let logger = Logger(subsystem: "cz.ondralinek.VdvMap", category: "vehicle-detail")

    private let configuration: VehicleRequestConfiguration
    private let session: URLSession

    init(
        configuration: VehicleRequestConfiguration = .live,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func fetchDetail(for vehicle: Vehicle) async throws -> VehicleDetail {
        let infoHTML = try await loadHTML(
            VehicleRequestFactory.makeInfoWindowRequest(
                vehicleID: vehicle.id,
                configuration: configuration
            )
        )
        let info = try VehicleDetailHTMLParser.parseInfoWindow(infoHTML)

        // The stop list is a bonus: without it the card still has the line,
        // the service number and the stop the vehicle is serving.
        var stops: [RunStop] = []
        do {
            let timetableHTML = try await loadHTML(
                VehicleRequestFactory.makeTimetableRequest(
                    vehicleID: vehicle.id,
                    configuration: configuration
                )
            )
            stops = runStops(from: timetableHTML, for: info, fallbackLine: vehicle.line)
        } catch {
            Self.logger.debug(
                "Timetable for vehicle \(vehicle.id, privacy: .public) unavailable: \(String(describing: error), privacy: .public)"
            )
        }

        return VehicleDetail(
            lineCode: LineCode(raw: info.line ?? vehicle.line),
            serviceNumber: info.serviceNumber,
            isBarrierFree: info.isBarrierFree,
            stopName: info.stopName,
            reportedDelayMinutes: info.reportedDelayMinutes,
            runStops: stops
        )
    }

    /// Stops of `timetableHTML`, but only when the page really describes this
    /// vehicle's run.
    ///
    /// The endpoint resolves the run itself and will happily answer with a
    /// different one. A stop list that does not belong to the vehicle produces a
    /// confidently wrong next stop, which is worse than none, so the run the
    /// page says it describes is checked before the stops are used.
    private func runStops(
        from timetableHTML: String,
        for info: VehicleDetailHTMLParser.InfoWindow,
        fallbackLine: String
    ) -> [RunStop] {
        guard let label = try? VehicleDetailHTMLParser.parseRunLabel(timetableHTML) else {
            return []
        }

        let wantedLine = LineCode(raw: info.line ?? fallbackLine).number
        guard LineCode(raw: label.line).number == wantedLine else {
            Self.logger.debug(
                "Timetable describes line \(label.line, privacy: .public) instead of \(wantedLine, privacy: .public); ignoring it."
            )
            return []
        }
        if let serviceNumber = info.serviceNumber, serviceNumber != label.serviceNumber {
            Self.logger.debug(
                "Timetable describes run \(label.serviceNumber, privacy: .public) instead of \(serviceNumber, privacy: .public); ignoring it."
            )
            return []
        }

        return (try? VehicleDetailHTMLParser.parseRunStops(timetableHTML)) ?? []
    }

    private func loadHTML(_ request: URLRequest) async throws -> String {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw VehicleAPIError.malformedPayload("The response was not an HTTP response.")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw VehicleAPIError.httpStatus(httpResponse.statusCode)
            }
            guard let html = String(data: data, encoding: .utf8) else {
                throw VehicleAPIError.malformedPayload("The response was not text.")
            }
            return html
        } catch let error as VehicleAPIError {
            throw error
        } catch {
            throw VehicleAPIError.transport(
                (error as? URLError)?.localizedDescription ?? error.localizedDescription
            )
        }
    }
}
