import SwiftUI

/// The official timetable index: whether it is here, whether it is still the
/// published one, and how to get it - or get rid of it.
struct TimetablesView: View {
    let isReady: Bool
    let isDownloading: Bool
    let isCheckingForUpdates: Bool
    let downloadedAt: Date?
    /// When the archive the index was read from was published, when it said so.
    let archivePublishedAt: Date?
    /// Whether that archive is still the one the portal offers.
    let update: TimetableUpdate
    let errorMessage: String?
    let knownLineCount: Int
    /// Whether the map fills in the lines the feed has gone quiet about.
    let showsCalculatedServices: Bool
    /// How many of the region's lines have a timetable on the phone so far.
    let coveredLineCount: Int
    /// True while those timetables are being read.
    let isReadingLines: Bool
    let onDownload: () -> Void
    let onCheckForUpdates: () -> Void
    let onForget: () -> Void
    let onSetShowsCalculatedServices: (Bool) -> Void

    var body: some View {
        Form {
            Section {
                if isReady, let downloadedAt {
                    LabeledContent("Downloaded") {
                        Text(downloadedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let archivePublishedAt {
                        LabeledContent("Published") {
                            Text(archivePublishedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    LabeledContent("Lines") {
                        Text(String(format: String(localized: "%lld"), knownLineCount))
                    }

                    if let status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(update == .outdated ? Color.orange : Color.secondary)
                    }

                    Button(update == .outdated ? "Update now" : "Download again", action: onDownload)
                        .disabled(isDownloading || isCheckingForUpdates)

                    Button("Check for updates", action: onCheckForUpdates)
                        .disabled(isDownloading || isCheckingForUpdates)

                    Button("Remove", role: .destructive, action: onForget)
                } else {
                    Button("Download timetables", action: onDownload)
                        .disabled(isDownloading)
                }

                if isDownloading {
                    busy("Reading the timetable index…")
                } else if isCheckingForUpdates {
                    busy("Checking for updates…")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Downloads the index of the official timetable archive (a couple of megabytes), so the selected vehicle can list all of its stops with the times they are actually expected. Each line's timetable is then fetched on its own, a few kilobytes at a time. Checking for updates asks the archive which version it is, which costs about a kilobyte and nothing else.")
            }

            Section {
                Toggle("Fill in lines the feed leaves out", isOn: calculatedServicesBinding)
                    .disabled(!isReady)

                if isReady, showsCalculatedServices {
                    LabeledContent("Lines read") {
                        Text(String(format: String(localized: "%lld of %lld"),
                                    coveredLineCount, knownLineCount))
                    }
                    if isReadingLines {
                        busy("Reading the region's timetables…")
                    }
                }
            } header: {
                Text("The map")
            } footer: {
                Text("The feed goes quiet about whole lines for stretches of the day. With this on, the map draws a line the timetable says should be running at the stop its service is due at, marked with an exclamation triangle. It is the published stop, not a measured position, and it does not move. Needs every line's timetable, which is fetched a few kilobytes at a time and kept on the phone; nothing is sent anywhere.")
            }
        }
        .navigationTitle("Timetables")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var calculatedServicesBinding: Binding<Bool> {
        Binding(get: { showsCalculatedServices }, set: onSetShowsCalculatedServices)
    }

    /// What the server said, once it has been asked.
    private var status: String? {
        switch update {
        case .unchecked:
            return nil
        case .upToDate:
            return String(localized: "Up to date.")
        case .outdated:
            return String(localized: "A newer archive is published.")
        case .cannotTell:
            return String(localized: "This index does not record which archive it came from.")
        }
    }

    private func busy(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}
