import SwiftUI

/// What a finished timetable download brought, and the way into it.
///
/// The download used to end in silence: the settings screen's numbers changed and
/// nothing said what had arrived. This is the receipt - how many lines, from which
/// publication - and "More info" is the door into the lines themselves, so the next
/// question ("what does it say?") is one tap away rather than a hunt through
/// settings.
struct TimetableDownloadSummaryView: View {
    let summary: TimetableDownloadSummary
    let store: LineTimetableStore
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Lines in the mapping") {
                        Text(String(format: String(localized: "%lld"), summary.lineCount))
                    }
                    LabeledContent("Entries in the archive") {
                        Text(String(format: String(localized: "%lld"), summary.entryCount))
                    }
                    LabeledContent("Published") {
                        Text(summary.publishedAt.map(Self.date) ?? String(localized: "Not recorded"))
                    }
                    LabeledContent("Downloaded") {
                        Text(Self.date(summary.downloadedAt))
                    }
                    if let size = summary.sizeText {
                        LabeledContent("Archive size") { Text(size) }
                    }
                    LabeledContent("Lines on this phone") {
                        Text(String(format: String(localized: "%lld"), summary.readableLines))
                    }
                } footer: {
                    Text("The index says where every line's timetable lives in the ministry's archive. Each line is then fetched on its own, the first time something needs it, and kept on the phone.")
                }

                Section {
                    NavigationLink {
                        DownloadedLinesView(store: store)
                    } label: {
                        Label("More info", systemImage: "tray.full")
                    }
                } footer: {
                    Text("Browse the lines whose timetables are on this phone: their runs, their stops, and the tables they were read from.")
                }
            }
            .navigationTitle(Text("Timetables downloaded"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
