import Foundation

/// The stops a widget can be told about.
///
/// The widget has its own copy of the shipped stop table, so it can offer a stop
/// before the app has ever been opened on it. What it cannot do is download the
/// archive index, so a board for a stop the app has not prepared explains itself
/// instead of waiting.
enum StopIndex {
    /// Stops matching what has been typed, limited to the ones some line calls at:
    /// a stop nothing serves would be a board with no rows for ever.
    static func matching(_ text: String) -> [String] {
        let table = StopPositions.shipped
        return table.names(matching: text,
                           excluding: { table.lines(atStopNamed: $0).isEmpty },
                           limit: 20)
    }

    /// What the configuration sheet offers before anything is typed: the stops the
    /// user already starred, which is the list they are most likely to want a board
    /// for. Empty when there are none, and then the sheet is a search field.
    static func suggested() -> [String] {
        UserDefaultsStarredStopsStore().load().orderedForDisplay
    }
}
