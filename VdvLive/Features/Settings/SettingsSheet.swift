import SwiftUI

/// Settings screen: how often the map refreshes itself, and in which language.
struct SettingsSheet: View {
    let settings: AppSettings
    let onSetAutoRefreshEnabled: (Bool) -> Void
    let onSetAutoRefreshInterval: (TimeInterval) -> Void
    let onSetLanguage: (AppLanguage) -> Void
    /// Whether the map opens on the current location when it starts.
    let onSetStartsAtCurrentLocation: (Bool) -> Void
    /// Forgets the viewport the lock button saved.
    let onClearSavedMapView: () -> Void

    /// State of the official timetable index, owned by the map screen.
    let isTimetableReady: Bool
    let isDownloadingTimetables: Bool
    let downloadedAt: Date?
    let timetableErrorMessage: String?
    let knownLineCount: Int
    let onDownloadTimetables: () -> Void
    let onForgetTimetables: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Automatic refresh", isOn: autoRefreshEnabledBinding)

                    Picker("Refresh interval", selection: autoRefreshIntervalBinding) {
                        ForEach(intervalOptions, id: \.self) { interval in
                            Text(Self.intervalLabel(interval)).tag(interval)
                        }
                    }
                    .disabled(!settings.autoRefreshEnabled)
                } header: {
                    Text("Refresh")
                } footer: {
                    Text(
                        String(
                            format: String(
                                localized: "The feed reports new positions every few seconds. Asking for them more often than every %lld s only costs battery."
                            ),
                            Int(AppSettings.minimumAutoRefreshInterval)
                        )
                    )
                }

                Section {
                    Picker("Language", selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("Czech is the default. A language change takes effect the next time the app starts.")
                }

                Section {
                    Toggle("Open at my location", isOn: startsAtCurrentLocationBinding)

                    if settings.savedMapView != nil {
                        Button("Clear saved view", role: .destructive, action: onClearSavedMapView)
                    }
                } header: {
                    Text("Opening the map")
                } footer: {
                    Text("The map starts about 10 km around your position, read once when the app starts and never sent anywhere. The lock button on the map remembers the view you are looking at instead; press it again to forget that view.")
                }

                Section {
                    if isTimetableReady, let downloadedAt {
                        LabeledContent("Downloaded") {
                            Text(downloadedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        LabeledContent("Lines") {
                            Text(String(format: String(localized: "%lld"), knownLineCount))
                        }
                        Button("Download again", action: onDownloadTimetables)
                        Button("Remove", role: .destructive, action: onForgetTimetables)
                    } else {
                        Button("Download timetables", action: onDownloadTimetables)
                            .disabled(isDownloadingTimetables)
                    }

                    if isDownloadingTimetables {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Reading the timetable index…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let timetableErrorMessage {
                        Text(timetableErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Timetables")
                } footer: {
                    Text("Downloads the index of the official timetable archive (a couple of megabytes), so the selected vehicle can list all of its stops with the times they are actually expected. Each line's timetable is then fetched on its own, a few kilobytes at a time.")
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

    /// Offered intervals, plus the current one if it is not among them, so that
    /// a value written by another build still shows up in the picker.
    private var intervalOptions: [TimeInterval] {
        let selectable = AppSettings.selectableAutoRefreshIntervals
        guard !selectable.contains(settings.autoRefreshInterval) else { return selectable }
        return (selectable + [settings.autoRefreshInterval]).sorted()
    }

    private var autoRefreshEnabledBinding: Binding<Bool> {
        Binding(get: { settings.autoRefreshEnabled }, set: onSetAutoRefreshEnabled)
    }

    private var autoRefreshIntervalBinding: Binding<TimeInterval> {
        Binding(get: { settings.autoRefreshInterval }, set: onSetAutoRefreshInterval)
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { settings.language }, set: onSetLanguage)
    }

    private var startsAtCurrentLocationBinding: Binding<Bool> {
        Binding(get: { settings.startsAtCurrentLocation }, set: onSetStartsAtCurrentLocation)
    }

    /// "30 s" for the short intervals, "2 min" for the long ones.
    static func intervalLabel(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return String(format: String(localized: "%lld s"), Int(interval))
        }
        return String(format: String(localized: "%lld min"), Int(interval / 60))
    }
}

#Preview {
    SettingsSheet(
        settings: .default,
        onSetAutoRefreshEnabled: { _ in },
        onSetAutoRefreshInterval: { _ in },
        onSetLanguage: { _ in },
        onSetStartsAtCurrentLocation: { _ in },
        onClearSavedMapView: {},
        isTimetableReady: false,
        isDownloadingTimetables: false,
        downloadedAt: nil,
        timetableErrorMessage: nil,
        knownLineCount: 381,
        onDownloadTimetables: {},
        onForgetTimetables: {}
    )
}
