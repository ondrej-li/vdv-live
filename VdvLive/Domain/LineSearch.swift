import Foundation

/// What the ad hoc search shows for what the reader has typed.
///
/// The pinned lines come first because they are the ones the reader already cares
/// about, then everything the feed is reporting. A line that is both appears once: two
/// rows for one line would make the list look longer than it is and give two targets
/// for the same jump.
enum LineSearch {
    /// How many lines a search offers before it stops being a list and starts being a
    /// wall. Stops are capped the same way by the stop table itself.
    static let limit = 12

    static func matches(_ query: String,
                        pinned: [LineSummary],
                        running: [LineSummary],
                        limit: Int = LineSearch.limit) -> [LineSummary] {
        let wanted = FavouriteLines.normalize(query)
        guard !wanted.isEmpty else { return [] }

        var seen: Set<String> = []
        let found = (pinned + running).filter { summary in
            guard summary.line.contains(wanted) else { return false }
            return seen.insert(summary.line).inserted
        }
        return Array(found.prefix(limit))
    }
}
