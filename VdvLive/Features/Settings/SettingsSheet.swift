import SwiftUI

/// Settings, in four parts: what the app prefers, the pinned lines, the official
/// timetables, and where the data comes from.
///
/// Each part gets a screen of its own rather than one long form: nothing is more
/// than two taps away, and no screen has to be scrolled to be read.
struct SettingsSheet: View {
    let settings: AppSettings

    /// Preferences: refresh, language, the grouping radius and the position.
    let onSetAutoRefreshEnabled: (Bool) -> Void
    let onSetAutoRefreshInterval: (TimeInterval) -> Void
    let onSetLanguage: (AppLanguage) -> Void
    let onSetAppearance: (AppAppearance) -> Void
    let onSetClusterRadius: (Double) -> Void
    let onSetShowsCurrentLocation: (Bool) -> Void
    let onSetFollowsCurrentLocation: (Bool) -> Void
    let onSetStartsAtCurrentLocation: (Bool) -> Void
    let onSetShowsStops: (Bool) -> Void
    let onClearSavedMapView: () -> Void

    /// Pinned lines, which the star in the header manages too.
    let favouriteLines: FavouriteLines
    let runningLines: [LineSummary]
    let summaryForLine: (String) -> LineSummary
    let showsOnlyPinned: Bool
    let onSetShowsOnlyPinned: (Bool) -> Void
    let onToggleLine: (String) -> Void
    let onPinLine: (String) -> Void
    let onShowLine: (String) -> Void

    /// State of the official timetable index.
    let isTimetableReady: Bool
    let isDownloadingTimetables: Bool
    let isCheckingTimetables: Bool
    let downloadedAt: Date?
    let archivePublishedAt: Date?
    let timetableUpdate: TimetableUpdate
    let timetableErrorMessage: String?
    let knownLineCount: Int
    let onDownloadTimetables: () -> Void
    let onCheckTimetables: () -> Void
    let onForgetTimetables: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        PreferencesView(
                            settings: settings,
                            onSetAutoRefreshEnabled: onSetAutoRefreshEnabled,
                            onSetAutoRefreshInterval: onSetAutoRefreshInterval,
                            onSetLanguage: onSetLanguage,
                            onSetAppearance: onSetAppearance,
                            onSetClusterRadius: onSetClusterRadius,
                            onSetShowsCurrentLocation: onSetShowsCurrentLocation,
                            onSetFollowsCurrentLocation: onSetFollowsCurrentLocation,
                            onSetStartsAtCurrentLocation: onSetStartsAtCurrentLocation,
                            onSetShowsStops: onSetShowsStops,
                            onClearSavedMapView: onClearSavedMapView
                        )
                    } label: {
                        SettingsRow(
                            title: "Preferences",
                            systemImage: "slider.horizontal.3",
                            subtitle: "Refresh, language, appearance and the map"
                        )
                    }

                    NavigationLink {
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
                    } label: {
                        SettingsRow(
                            title: "Pinned lines",
                            systemImage: "star",
                            subtitle: "Pin and unpin bus lines"
                        )
                    }

                    NavigationLink {
                        TimetablesView(
                            isReady: isTimetableReady,
                            isDownloading: isDownloadingTimetables,
                            isCheckingForUpdates: isCheckingTimetables,
                            downloadedAt: downloadedAt,
                            archivePublishedAt: archivePublishedAt,
                            update: timetableUpdate,
                            errorMessage: timetableErrorMessage,
                            knownLineCount: knownLineCount,
                            onDownload: onDownloadTimetables,
                            onCheckForUpdates: onCheckTimetables,
                            onForget: onForgetTimetables
                        )
                    } label: {
                        SettingsRow(
                            title: "Timetables",
                            systemImage: "calendar",
                            subtitle: "Download or remove the official timetables"
                        )
                    }

                    NavigationLink {
                        AcknowledgementsView()
                    } label: {
                        SettingsRow(
                            title: "Acknowledgements",
                            systemImage: "info.circle",
                            subtitle: "Where the data comes from"
                        )
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One row of the settings list: a symbol, what the part is called, and a line
/// saying what is behind it.
private struct SettingsRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
