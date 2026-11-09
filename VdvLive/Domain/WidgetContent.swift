import CoreLocation
import Foundation

/// What a departure board widget has to say.
///
/// The first two cases are the widget explaining itself: a board needs a stop to
/// be about, and the timetables it is built from are downloaded in the app, so
/// there is a state in which the answer is "not yet" rather than "nothing".
enum WidgetBoardState: Equatable, Sendable {
    /// No stop has been chosen in the widget's configuration.
    case needsStop
    /// The archive index is not on the device, so no line can be read.
    case needsTimetables
    case board(stopName: String, rows: [StopBoardEntry])
}

/// Where a widget is looking from.
///
/// The traffic widget used to look from one place only - the last fix the app took -
/// which made it a map of wherever the reader happened to be when they last opened
/// the app. A place can be named instead: a stop from the shipped table, which is
/// what the app itself is built around and what somebody planning a journey cares
/// about. Naming nothing keeps the old behaviour, so a widget picked for "around me"
/// still works without configuration.
struct WidgetOrigin: Equatable, Sendable {
    /// The middle of the question, `nil` when nothing can place it.
    let coordinate: CLLocationCoordinate2D?
    /// The stop it was asked about, `nil` when it is the reader's own position.
    let name: String?

    /// The origin a configuration describes.
    ///
    /// - Parameters:
    ///   - stopName: the stop chosen in the widget's configuration, if any.
    ///   - table: the shipped stop positions, which is where a stop's own position
    ///     comes from - the timetable archive publishes none.
    ///   - position: the last fix the app took, used when no stop was chosen.
    static func resolve(stopNamed stopName: String?,
                        in table: StopPositions,
                        position: CLLocationCoordinate2D?) -> WidgetOrigin {
        guard let stopName, !stopName.isEmpty else {
            return WidgetOrigin(coordinate: position, name: nil)
        }
        return WidgetOrigin(coordinate: table.position(forStopNamed: stopName)?.coordinate,
                            name: stopName)
    }

    static func == (lhs: WidgetOrigin, rhs: WidgetOrigin) -> Bool {
        lhs.name == rhs.name
            && lhs.coordinate?.latitude == rhs.coordinate?.latitude
            && lhs.coordinate?.longitude == rhs.coordinate?.longitude
    }
}

/// What the starred traffic widget has to say.
enum WidgetTrafficState: Equatable, Sendable {
    /// Nothing is pinned, so there is no traffic of the reader's own to show.
    case needsPinnedLines
    /// The app has never had a fix, so "around" has no middle.
    case needsPosition
    case vehicles([NearbyVehicle])
}

/// Turns the app's data into what a widget draws.
///
/// Kept apart from WidgetKit so the rules - which rows survive being old, how many
/// fit, what an empty answer means - are testable without a widget host.
enum WidgetContent {
    /// A row is dropped this long after its time, so a timeline entry generated
    /// just before a departure does not show a bus that has already gone.
    static let boardGraceMinutes = 1

    /// The board a widget shows: what is still to come, soonest first.
    ///
    /// - Parameters:
    ///   - stopName: the stop chosen in the configuration, `nil` when none was.
    ///   - timetables: the lines serving the stop, or `nil` when they cannot be
    ///     read yet because the archive index has not been downloaded.
    ///   - lineDelays: what the feed reports for the vehicles of those lines;
    ///     `StopBoard` places each one on the run its destination names.
    ///   - limit: how many rows the widget family has room for.
    static func board(stopName: String?,
                      timetables: [LineTimetable]?,
                      lineDelays: [LineDelay] = [],
                      now: TimeOfDay,
                      limit: Int = 4) -> WidgetBoardState {
        guard let stopName, !stopName.isEmpty else { return .needsStop }
        guard let timetables else { return .needsTimetables }

        let entries = StopBoard.entries(at: stopName, in: timetables, lineDelays: lineDelays, now: now)
            .filter { ($0.expected ?? $0.scheduled).minutes >= now.minutes - boardGraceMinutes }
        return .board(stopName: stopName, rows: Array(entries.prefix(max(limit, 0))))
    }

    /// The pinned lines' traffic around the reader.
    static func traffic(vehicles: [Vehicle],
                        pinnedTo lines: FavouriteLines,
                        from coordinate: CLLocationCoordinate2D?,
                        limit: Int = NearbyVehicles.limit) -> WidgetTrafficState {
        guard !lines.isEmpty else { return .needsPinnedLines }
        guard let coordinate else { return .needsPosition }

        return .vehicles(NearbyVehicles.nearby(in: vehicles,
                                                pinnedTo: lines,
                                                from: coordinate,
                                                limit: limit))
    }

    /// The stops the widget's configuration offers before anything is typed.
    ///
    /// A picker that opens on an empty list looks broken, so this always answers with
    /// something: the starred stops first - the ones the reader already said they care
    /// about - then the stops of the lines they pinned, then the busiest stops in the
    /// table so that there is a way in even before the app has been used.
    static func suggestedStops(in table: StopPositions,
                               starred: StarredStops = StarredStops(),
                               pinned: FavouriteLines = FavouriteLines(),
                               limit: Int = 20) -> [String] {
        guard limit > 0 else { return [] }

        // A stop nothing calls at would be a board with no rows for ever.
        let served = table.allNames.filter { !table.lines(atStopNamed: $0).isEmpty }
        var chosen: [String] = []
        var seen: Set<String> = []

        func add(_ name: String) {
            guard chosen.count < limit else { return }
            let key = StarredStops.key(for: name)
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            chosen.append(name)
        }

        for name in starred.orderedForDisplay { add(name) }
        for name in served where table.lines(atStopNamed: name).contains(where: pinned.contains) {
            add(name)
        }

        let lineCounts = served.reduce(into: [String: Int]()) { counts, name in
            counts[name] = table.lines(atStopNamed: name).count
        }
        for name in served.sorted(by: { left, right in
            let leftCount = lineCounts[left] ?? 0
            let rightCount = lineCounts[right] ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            return left.localizedStandardCompare(right) == .orderedAscending
        }) {
            add(name)
        }

        return chosen
    }
}
