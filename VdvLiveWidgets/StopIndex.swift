import Foundation

/// The stops a widget can be told about.
///
/// The widget has its own copy of the shipped stop table, so it can offer a stop
/// before the app has ever been opened on it. What it cannot do is download the
/// archive index, so a board for a stop the app has not prepared explains itself
/// instead of waiting.
enum StopIndex {
    /// Stops matching what has been typed, limited to the ones some line calls at: a
    /// stop nothing serves would be a board with no rows for ever.
    ///
    /// An empty search is what the picker shows before anything is typed, so it
    /// answers with the suggestions rather than with nothing.
    static func matching(_ text: String) -> [String] {
        let table = StopPositions.shipped
        guard !StopNameMatching.key(for: text).isEmpty else { return suggested(in: table) }
        return table.names(matching: text,
                           excluding: { table.lines(atStopNamed: $0).isEmpty },
                           limit: 20)
    }

    /// What the configuration sheet offers before anything is typed.
    static func suggested() -> [String] {
        suggested(in: StopPositions.shipped)
    }

    private static func suggested(in table: StopPositions) -> [String] {
        WidgetContent.suggestedStops(in: table,
                                     starred: UserDefaultsStarredStopsStore().load(),
                                     pinned: UserDefaultsFavouriteLinesStore().load())
    }
}
