import SwiftUI

/// The official timetable index: whether it is here, how to get it, and how to
/// get rid of it again.
struct TimetablesView: View {
    let isReady: Bool
    let isDownloading: Bool
    let downloadedAt: Date?
    let errorMessage: String?
    let knownLineCount: Int
    let onDownload: () -> Void
    let onForget: () -> Void

    var body: some View {
        Form {
            Section {
                if isReady, let downloadedAt {
                    LabeledContent("Downloaded") {
                        Text(downloadedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Lines") {
                        Text(String(format: String(localized: "%lld"), knownLineCount))
                    }
                    Button("Download again", action: onDownload)
                    Button("Remove", role: .destructive, action: onForget)
                } else {
                    Button("Download timetables", action: onDownload)
                        .disabled(isDownloading)
                }

                if isDownloading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Reading the timetable index…")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Downloads the index of the official timetable archive (a couple of megabytes), so the selected vehicle can list all of its stops with the times they are actually expected. Each line's timetable is then fetched on its own, a few kilobytes at a time.")
            }
        }
        .navigationTitle("Timetables")
        .navigationBarTitleDisplayMode(.inline)
    }
}
