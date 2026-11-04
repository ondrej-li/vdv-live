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
    ///   - delays: minutes late by the feed's line code; a run's own delay is
    ///     matched by `StopBoard`.
    ///   - limit: how many rows the widget family has room for.
    static func board(stopName: String?,
                      timetables: [LineTimetable]?,
                      delays: [String: Int] = [:],
                      now: TimeOfDay,
                      limit: Int = 4) -> WidgetBoardState {
        guard let stopName, !stopName.isEmpty else { return .needsStop }
        guard let timetables else { return .needsTimetables }

        let entries = StopBoard.entries(at: stopName, in: timetables, delays: delays, now: now)
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
}
