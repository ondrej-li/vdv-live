import Foundation

/// What a board widget needs before it can put times on a stop.
///
/// Fetched once per timeline rather than once per entry: the delays and the
/// timetables are the expensive part, and they do not change between two entries
/// a few minutes apart - only which rows are still ahead does.
struct DepartureBoardMaterial {
    let stopName: String?
    let timetables: [LineTimetable]?
    let delays: [String: Int]

    func state(at date: Date, limit: Int) -> WidgetBoardState {
        WidgetContent.board(stopName: stopName,
                            timetables: timetables,
                            delays: delays,
                            now: TimeOfDay(date),
                            limit: limit)
    }
}

/// Where the widgets get their data from.
///
/// The app is the one that downloads the timetable archive, so a widget reads the
/// index and the entries the app put in the shared container. What it does fetch
/// itself is the live feed, once per timeline, because that is the only way a
/// delay on the home screen is ever current.
@MainActor
enum WidgetDataSource {
    /// The stop's board, or the reason there is none.
    static func boardMaterial(stopName: String?) async -> DepartureBoardMaterial {
        guard let stopName, !stopName.isEmpty else {
            return DepartureBoardMaterial(stopName: nil, timetables: nil, delays: [:])
        }

        let store = LineTimetableStore()
        guard store.isReady else {
            return DepartureBoardMaterial(stopName: stopName, timetables: nil, delays: [:])
        }

        var timetables: [LineTimetable] = []
        for line in StopPositions.shipped.lines(atStopNamed: stopName) {
            // A line the archive has moved on from must not take the board with it.
            if let timetable = try? await store.timetable(forLine: line) {
                timetables.append(timetable)
            }
        }

        return DepartureBoardMaterial(stopName: stopName,
                                      timetables: timetables,
                                      delays: delays(of: await vehicles()))
    }

    /// The pinned lines' traffic, and the reasons there might be none.
    static func trafficState(limit: Int) async -> WidgetTrafficState {
        WidgetContent.traffic(vehicles: await vehicles(),
                              pinnedTo: UserDefaultsFavouriteLinesStore().load(),
                              from: LastKnownPositionStore().load(),
                              limit: limit)
    }

    /// The live feed, or nothing when it cannot be reached: a widget that shows an
    /// error where a departure board should be is worse than one that keeps the
    /// board it can still compute from the timetable.
    private static func vehicles() async -> [Vehicle] {
        (try? await VehicleAPIClient().fetchVehicles())?.vehicles ?? []
    }

    /// Minutes late by line, the way the app reads them: the feed names the line
    /// but not the run, so the worst vehicle of a line speaks for it.
    private static func delays(of vehicles: [Vehicle]) -> [String: Int] {
        vehicles.reduce(into: [:]) { delays, vehicle in
            guard let minutes = vehicle.delay.minutes else { return }
            delays[vehicle.line] = max(minutes, delays[vehicle.line] ?? minutes)
        }
    }
}
