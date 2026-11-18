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
    let onDownload: () -> Void
    let onCheckForUpdates: () -> Void
    let onForget: () -> Void

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
        }
        .navigationTitle("Timetables")
        .navigationBarTitleDisplayMode(.inline)
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
