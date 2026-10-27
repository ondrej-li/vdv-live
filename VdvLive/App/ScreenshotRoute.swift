import Foundation

/// Launch arguments that open a screen normally reached by a tap, so the App Store
/// artwork can be captured from a clean simulator (see `make screenshots`).
///
/// Every answer here is `false` or `nil` in a Release build, so none of it can
/// reach the archive shipped to the App Store - the flags only exist to photograph
/// screens that would otherwise need a finger on the glass.
enum ScreenshotRoute {
    /// Opens Settings from the map's gear.
    static var opensSettings: Bool { isOn("-screenshotSettings") }
    /// Reads the timetable index before doing anything else, so the departure board
    /// and the timetable have something to show.
    static var downloadsTimetables: Bool { isOn("-screenshotDownloadTimetables") }
    /// Starts the vehicle card with its stops drawer open, which is where the
    /// timetable is drawn.
    static var startsExpanded: Bool { isOn("-screenshotExpandTimetable") }
    /// Shows every reporting vehicle rather than only the pinned lines, so a shot
    /// does not depend on what an earlier session left pinned.
    static var showsAllVehicles: Bool { isOn("-screenshotAllVehicles") }

    /// The stop whose departure board to open, as the shipped position table names it.
    static var boardStopName: String? { value(after: "-screenshotBoard") }
    /// The line whose first running vehicle to select, so its detail card opens.
    static var serviceLine: String? { value(after: "-screenshotService") }

    private static func isOn(_ flag: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(flag)
        #else
        false
        #endif
    }

    private static func value(after flag: String) -> String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        return value.hasPrefix("-") ? nil : value
        #else
        nil
        #endif
    }
}
