import SwiftUI

/// Sheet for managing pinned lines, opened with the star in the header.
///
/// The list itself is shared with the settings screen, which pushes the same
/// view; this only adds the navigation bar and the way out of it.
struct FavouriteLinesSheet: View {
    let favouriteLines: FavouriteLines
    let runningLines: [LineSummary]
    let summaryForLine: (String) -> LineSummary
    let showsOnlyPinned: Bool
    let onSetShowsOnlyPinned: (Bool) -> Void
    let onToggleLine: (String) -> Void
    let onPinLine: (String) -> Void
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
