import Foundation

/// What a board widget needs before it can put times on a stop.
///
/// Fetched once per timeline rather than once per entry: the delays and the
/// timetables are the expensive part, and they do not change between two entries
/// a few minutes apart - only which rows are still ahead does.
struct DepartureBoardMaterial {
    let stopName: String?
    let timetables: [LineTimetable]?
    let delays: [LineDelay]

    func state(at date: Date, limit: Int) -> WidgetBoardState {
        WidgetContent.board(stopName: stopName,
                            timetables: timetables,
                            lineDelays: delays,
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
            return DepartureBoardMaterial(stopName: nil, timetables: nil, delays: [])
        }

        let store = LineTimetableStore()
        guard store.isReady else {
            return DepartureBoardMaterial(stopName: stopName, timetables: nil, delays: [])
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

    /// The pinned lines' traffic around a place, and the reasons there might be none.
    static func trafficState(around origin: WidgetOrigin, limit: Int) async -> WidgetTrafficState {
        WidgetContent.traffic(vehicles: await vehicles(),
                              pinnedTo: UserDefaultsFavouriteLinesStore().load(),
                              from: origin.coordinate,
                              limit: limit)
    }

    /// The live feed, or nothing when it cannot be reached: a widget that shows an
    /// error where a departure board should be is worse than one that keeps the
    /// board it can still compute from the timetable.
    private static func vehicles() async -> [Vehicle] {
        (try? await VehicleAPIClient().fetchVehicles())?.vehicles ?? []
    }

    /// What the feed reports for each vehicle, with where it is going: the same
    /// reports the app's board uses, so a delay lands on the run it belongs to
    /// rather than on whichever row of the line happens to be nearest.
    private static func delays(of vehicles: [Vehicle]) -> [LineDelay] {
        vehicles.compactMap { vehicle in
            guard let minutes = vehicle.delay.minutes,
                  let destination = vehicle.destination else { return nil }
            return LineDelay(lineNumber: vehicle.line,
                             minutes: minutes,
                             destination: destination)
        }
    }
}
