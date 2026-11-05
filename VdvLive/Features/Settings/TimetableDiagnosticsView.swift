import SwiftUI

/// Why a line's timetable is or is not there, in the app's own words.
///
/// The board says "this line is not in the published timetable", which is true and
/// useless on its own: the line was there last week. What changed is the archive -
/// it was republished, and it renumbers every entry when it is - so this screen
/// shows which mapping is in force, what entries it names, whether the archive
/// still holds them, and what each line's last attempt did.
struct TimetableDiagnosticsView: View {
    let makeDiagnostics: () -> TimetableDiagnostics
    let isRefreshingMapping: Bool
    let mappingErrorMessage: String?
    let onRefreshMapping: () -> Void

    @State private var diagnostics: TimetableDiagnostics?
    @State private var filter = ""

    var body: some View {
        List {
            if let diagnostics {
                archiveSection(diagnostics)
                mappingSection(diagnostics)
                cacheSection(diagnostics)
                linesSection(diagnostics)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = diagnostics?.text
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel(Text("Copy diagnostics"))
                .disabled(diagnostics == nil)
            }
        }
        .onAppear { diagnostics = makeDiagnostics() }
        .refreshable { diagnostics = makeDiagnostics() }
    }

    private func archiveSection(_ diagnostics: TimetableDiagnostics) -> some View {
        Section {
            LabeledContent("Published") {
                Text(diagnostics.archive.publishedAt.map(Self.date) ?? "—")
            }
            LabeledContent("Downloaded") {
                Text(diagnostics.archive.downloadedAt.map(Self.date) ?? "—")
            }
            LabeledContent("Entries") {
                Text(String(format: String(localized: "%lld"), diagnostics.archive.entryCount))
            }
            LabeledContent("ETag") {
                Text(diagnostics.archive.etag ?? "—")
                    .font(.footnote.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } header: {
            Text("Archive")
        } footer: {
            Text("The index the app read from the ministry's archive. \"Entries\" is how many lines' timetables the archive held when the index was read; a republication replaces them, and renumbers every one.")
        }
    }

    private func mappingSection(_ diagnostics: TimetableDiagnostics) -> some View {
        Section {
            LabeledContent("Source") {
                switch diagnostics.mapping.source {
                case .bundled:
                    Text("In the app")
                case .published(let date):
                    Text(String(format: String(localized: "From the site, %@"), Self.date(date)))
                }
            }
            LabeledContent("Lines in the mapping") {
                Text(String(format: String(localized: "%lld"), diagnostics.mapping.lineCount))
            }

            Button(isRefreshingMapping ? "Refreshing…" : "Refresh mapping", action: onRefreshMapping)
                .disabled(isRefreshingMapping)

            if let mappingErrorMessage {
                Text(mappingErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Mapping")
        } footer: {
            Text("Which archive entry holds each line. The copy inside the app goes stale every time the ministry republishes the archive - that is what makes every line look \"not in the published timetable\" at once. Refreshing downloads the mapping published at vdv.ondralinek.cz.")
        }
    }

    private func cacheSection(_ diagnostics: TimetableDiagnostics) -> some View {
        Section {
            LabeledContent("Files") {
                Text(String(format: String(localized: "%lld"), diagnostics.cacheEntryCount))
            }
            LabeledContent("Size") {
                Text(ByteCountFormatter.string(fromByteCount: Int64(diagnostics.cacheBytes),
                                               countStyle: .file))
            }
        } header: {
            Text("Downloaded lines")
        }
    }

    private func linesSection(_ diagnostics: TimetableDiagnostics) -> some View {
        Section {
            let counts = diagnostics.counts
            LabeledContent("Downloaded") { Text("\(counts.downloaded)") }
            LabeledContent("Failed") { Text("\(counts.failed)") }
            LabeledContent("Not downloaded") { Text("\(counts.untouched)") }

            ForEach(visibleLines(diagnostics)) { line in
                row(line)
            }
        } header: {
            Text("Lines")
        } footer: {
            Text("One row per line the mapping knows. A downloaded line names the entry it came from and the line number that entry declares; a failed one says what went wrong.")
        }
    }

    private func visibleLines(_ diagnostics: TimetableDiagnostics) -> [TimetableDiagnostics.Line] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        let interesting = diagnostics.lines.filter { $0.record != nil || $0.hasFailed || $0.isDownloaded }
        guard !trimmed.isEmpty else { return interesting }
        return diagnostics.lines.filter { $0.lineNumber.contains(trimmed) }
    }

    private func row(_ line: TimetableDiagnostics.Line) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: symbol(line))
                    .foregroundStyle(tint(line))
                Text(LineCode(raw: line.lineNumber).number)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(LineCode(raw: line.lineNumber).raw)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(state(line))
                    .font(.caption)
                    .foregroundStyle(tint(line))
            }

            Text(detail(line))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ line: TimetableDiagnostics.Line) -> String {
        if line.isDownloaded { return "checkmark.circle.fill" }
        if line.hasFailed { return "exclamationmark.triangle.fill" }
        return "circle"
    }

    private func tint(_ line: TimetableDiagnostics.Line) -> Color {
        if line.isDownloaded { return .green }
        if line.hasFailed { return .orange }
        return .secondary
    }

    private func state(_ line: TimetableDiagnostics.Line) -> String {
        if line.isDownloaded { return String(localized: "Downloaded") }
        if let failure = line.record?.failure {
            return failure
        }
        return String(localized: "Not downloaded")
    }

    /// The entry the line came from, and what the archive says its candidates are.
    private func detail(_ line: TimetableDiagnostics.Line) -> String {
        let candidates = line.candidates
            .map { "\($0.entryName)\($0.isInIndex ? "" : " ✕")\($0.isOnDisk ? " ✓" : "")" }
            .joined(separator: "  ")
        if let record = line.record, let entry = record.entryName {
            return String(format: String(localized: "%@ → %@ · archive: %@"), entry,
                          record.declaredLineNumber ?? "?", candidates)
        }
        return String(format: String(localized: "archive: %@"), candidates)
    }

    private static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
