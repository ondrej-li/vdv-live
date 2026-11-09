import Foundation

/// Which run of its line a vehicle is working, as the map's own popup names it.
///
/// The positions feed names the line but not the run, and a board's rows are runs:
/// two services of one line pass the same stop in opposite directions, and a delay
/// that belongs to one of them is not the other's business. `/Ajax/OpenInfoWindow`
/// answers with `Spoj`, which is the number the timetables file the run under, so
/// asking it is what lets a delay be put on the row it was measured for.
struct VehicleRun: Hashable, Sendable {
    /// Line as the feed and the archive both write it: `766420`.
    let lineNumber: String
    /// JDF run number, `Spoj`.
    let serviceNumber: String
    /// The stop the vehicle is serving, when the popup names it.
    ///
    /// Held against the destination the points feed reports, it says whether the
    /// vehicle is still on its way or has arrived at the end of its run and is
    /// standing there - which is when its delay stops being a forecast.
    let stopName: String?

    /// Whether the vehicle has reached the stop its run ends at.
    ///
    /// A bus that has arrived keeps reporting the delay it arrived with for as long
    /// as it stands, which is how a board came to show the same number all morning.
    func hasArrived(at destination: String) -> Bool {
        guard let stopName, !stopName.isEmpty else { return false }
        return LineTimetable.stopNamesMatch(stopName, destination)
    }
}
