import Foundation

/// Everything needed to talk to the regional map feed.
struct VehicleRequestConfiguration: Sendable, Equatable {
    /// Origin of the map application.
    var baseURL: URL
    /// Path of the endpoint that powers the map, relative to ``baseURL``.
    var endpointPath: String
    /// Session cookie of the map application.
    ///
    /// The endpoint answers without one today, which is why the default is
    /// `nil`. It is kept configurable because the site does set a session
    /// cookie on first visit and a future deployment could start requiring it;
    /// paste the value of the `sznlbr` cookie from a browser session if that
    /// ever happens.
    var sessionCookie: String?
    /// Sent as `User-Agent`. The feed is behind a web front end, so the app
    /// identifies itself as the browser the endpoint was verified with.
    var userAgent: String
    var referer: String?
    var acceptLanguage: String?
    var timeout: TimeInterval

    static let live = VehicleRequestConfiguration(
        baseURL: URL(string: "https://mapavdv.kr-vysocina.cz")!,
        endpointPath: "Ajax/GetPoints",
        sessionCookie: nil,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36",
        referer: "https://mapavdv.kr-vysocina.cz/",
        acceptLanguage: "en-US,en;q=0.7",
        timeout: 20
    )
}

/// Builds the requests sent to the map feed.
///
/// `Sec-Fetch-*`, `sec-ch-ua*`, `Connection` and `Sec-GPC` from the original
/// browser request are deliberately not sent: URLSession manages connection
/// headers itself and the endpoint does not require the client hint headers.
enum VehicleRequestFactory {
    static func makeRequest(
        configuration: VehicleRequestConfiguration = .live
    ) -> URLRequest {
        makeRequest(
            path: configuration.endpointPath,
            queryItems: [],
            configuration: configuration
        )
    }

    /// Detail popup of one vehicle: line, service number, current stop.
    static func makeInfoWindowRequest(
        vehicleID: Int,
        configuration: VehicleRequestConfiguration = .live
    ) -> URLRequest {
        makeRequest(
            path: "Ajax/OpenInfoWindow",
            queryItems: [URLQueryItem(name: "id", value: String(vehicleID))],
            configuration: configuration
        )
    }

    /// Stop list of the run a vehicle is serving.
    ///
    /// `vehicleNumber` is the vehicle's id, not its line; `currentStopId` is
    /// what the site's own front end sends, and `0` means "not known".
    static func makeTimetableRequest(
        vehicleID: Int,
        currentStopID: String = "0",
        configuration: VehicleRequestConfiguration = .live
    ) -> URLRequest {
        makeRequest(
            path: "Ajax/GetTimetable",
            queryItems: [
                URLQueryItem(name: "vehicleNumber", value: String(vehicleID)),
                URLQueryItem(name: "currentStopId", value: currentStopID)
            ],
            configuration: configuration
        )
    }

    static func makeRequest(
        path: String,
        queryItems: [URLQueryItem],
        configuration: VehicleRequestConfiguration
    ) -> URLRequest {
        var url = configuration.baseURL.appending(path: path)
        if !queryItems.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = queryItems
            if let composed = components.url {
                url = composed
            }
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: configuration.timeout
        )
        request.httpMethod = "GET"
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        if let referer = configuration.referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let acceptLanguage = configuration.acceptLanguage {
            request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        }
        if let cookie = configuration.sessionCookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        return request
    }
}
