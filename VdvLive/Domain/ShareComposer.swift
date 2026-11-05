import Foundation

/// One thing to share: a subject for Mail, a message for everywhere else, and the
/// link that opens the same thing in the app.
struct ShareContent: Equatable, Sendable {
    let title: String
    let body: String
    let url: URL
}

/// What a share says, and where its link goes.
///
/// The text is built here rather than in the views so that both languages, the
/// wording of a delay and the shape of a link can be tested without a share sheet -
/// and so that a link the app shares is a link the app can open again.
enum ShareComposer {
    /// The stop of a shared link, or the line a vehicle was on.
    enum Target: Equatable, Sendable {
        case board(stopName: String)
        /// A vehicle by the line it runs and the service it serves; the service is
        /// what identifies it, and it may be gone by the time the link is opened.
        case vehicle(line: String, serviceNumber: String?)
    }

    /// Host of the pages and of the universal links the app answers.
    static let host = "vdv.ondralinek.cz"

    /// How many departures a shared board carries.
    ///
    /// Five: enough to show the shape of the next hour, few enough to stay one
    /// message rather than a wall of times.
    static let sharedBoardRows = 5

    // MARK: - Building

    /// A vehicle's position and delay, as a message someone can act on.
    ///
    /// - Parameters:
    ///   - line: the feed's line code, `764337`, which the text renders as `337`.
    ///   - destination: where the run ends, when the feed says.
    ///   - delayMinutes: minutes late, `nil` when the feed does not say.
    ///   - observedAt: when the app last read the feed, which is what the "as of"
    ///     time means - not when the bus passed somewhere.
    ///   - lastStop: the stop the vehicle is serving, when the detail was loaded.
    ///   - nextStop: the stop it is heading for, when the detail was loaded.
    static func vehicle(line: String,
                        destination: String?,
                        delayMinutes: Int?,
                        observedAt: Date?,
                        lastStop: String?,
                        nextStop: String?,
                        serviceNumber: String?) -> ShareContent {
        let number = LineCode(raw: line).number
        let heading = destination.map(displayName) ?? String(localized: "destination unknown")
        let delay = VehicleDelay(minutes: delayMinutes).displayText

        var lines: [String] = []
        lines.append(String(format: String(localized: "%@ → %@"), number, heading))
        if let observedAt {
            lines.append(String(format: String(localized: "%@ · as of %@"),
                                delay,
                                observedAt.formatted(date: .omitted, time: .shortened)))
        } else {
            lines.append(delay)
        }
        if let lastStop, let nextStop {
            lines.append(String(format: String(localized: "Last seen %@ · next %@"),
                                displayName(lastStop),
                                displayName(nextStop)))
        } else if let lastStop {
            lines.append(String(format: String(localized: "Last seen %@"), displayName(lastStop)))
        }

        return ShareContent(title: String(format: String(localized: "Line %@"), number),
                            body: lines.joined(separator: "\n"),
                            url: vehicleURL(line: line, serviceNumber: serviceNumber))
    }

    /// A stop's board, as the five departures a message can carry.
    static func board(stopName: String,
                      rows: [StopBoardEntry],
                      readAt: Date) -> ShareContent {
        let shown = rows.prefix(sharedBoardRows)
        var lines: [String] = [
            String(format: String(localized: "Departures from %@ (%@)"),
                   displayName(stopName),
                   readAt.formatted(date: .omitted, time: .shortened))
        ]
        for row in shown {
            lines.append("\(LineCode(raw: row.lineNumber).number) → "
                         + "\(row.destination.map(displayName) ?? String(localized: "destination unknown")) "
                         + "\(row.departureTime.text) (\(statusText(row)))")
        }
        return ShareContent(title: String(format: String(localized: "Departures from %@"),
                                          displayName(stopName)),
                            body: lines.joined(separator: "\n"),
                            url: boardURL(stopName: stopName))
    }

    /// `+3 min`, `on time`, or `podle řádu` while nothing is reporting.
    static func statusText(_ entry: StopBoardEntry) -> String {
        switch entry.status {
        case .scheduled: return String(localized: "scheduled")
        case .onTime: return VehicleDelay.minutes(0).displayText
        case .late(let minutes): return VehicleDelay.minutes(minutes).displayText
        case .early(let minutes): return VehicleDelay.minutes(-minutes).displayText
        }
    }

    // MARK: - Links

    /// `https://vdv.ondralinek.cz/s/?stop=Tel%C4%8D%2Caut.n%C3%A1dr.`
    static func boardURL(stopName: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/s/"
        components.queryItems = [URLQueryItem(name: "stop", value: stopName)]
        return components.url ?? URL(string: "https://\(host)/s/")!
    }

    /// `https://vdv.ondralinek.cz/s/?line=337&service=3`
    ///
    /// The line is the passenger-facing number, because that is what somebody
    /// reading the message would recognise, and because the licence area prefix is
    /// an implementation detail of the feed.
    static func vehicleURL(line: String, serviceNumber: String?) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/s/"
        var items = [URLQueryItem(name: "line", value: LineCode(raw: line).number)]
        if let serviceNumber, !serviceNumber.isEmpty {
            items.append(URLQueryItem(name: "service", value: serviceNumber))
        }
        components.queryItems = items
        return components.url ?? URL(string: "https://\(host)/s/")!
    }

    /// What a link the app was opened with is about, or `nil` when it is not ours.
    ///
    /// Accepts the share links and anything a person might paste back: either
    /// scheme, with or without the trailing slash, and query parameters in any
    /// order.
    static func target(from url: URL) -> Target? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              host == Self.host || host == "www.\(Self.host)" else { return nil }
        guard components.path == "/s" || components.path == "/s/" else { return nil }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }

        if let stop = value("stop") {
            return .board(stopName: stop)
        }
        if let line = value("line") {
            return .vehicle(line: line, serviceNumber: value("service"))
        }
        return nil
    }

    /// The archive writes "Zašovice,Nová Brtnice"; a person reads a space after the
    /// comma.
    static func displayName(_ stop: String) -> String {
        stop.replacingOccurrences(of: ",", with: ", ")
    }
}

private extension VehicleDelay {
    /// The delay a share reports, from the minutes the feed gave.
    init(minutes: Int?) {
        self = minutes.map(VehicleDelay.init(rawMinutes:)) ?? .unknown
    }
}
