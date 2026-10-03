import SwiftUI

/// The pinned lines, as the sheet the star in the header opens.
///
/// ``FavouriteLinesList`` is the content alone, so the stack, the title and the
/// way out live here, and the settings screen puts the same content inside its
/// own stack. The two should not drift apart: what a line looks like, and what
/// pinning it does, is decided in one place.
struct FavouriteLinesSheet: View {
    let favouriteLines: FavouriteLines
    let runningLines: [LineSummary]
    /// Summary for a pinned line, including the ones that are not running.
    let summaryForLine: (String) -> LineSummary
    /// Whether the map is showing pinned lines only.
    let showsOnlyPinned: Bool
    let onSetShowsOnlyPinned: (Bool) -> Void
    let onToggleLine: (String) -> Void
    /// Pins a line typed by hand.
    let onPinLine: (String) -> Void
    /// Asks the map to fly to the line.
    let onShowLine: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FavouriteLinesList(
                favouriteLines: favouriteLines,
                runningLines: runningLines,
                summaryForLine: summaryForLine,
                showsOnlyPinned: showsOnlyPinned,
                onSetShowsOnlyPinned: onSetShowsOnlyPinned,
                onToggleLine: onToggleLine,
                onPinLine: onPinLine,
                onShowLine: onShowLine
            )
            .navigationTitle("Pinned lines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
