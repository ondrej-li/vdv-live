import SwiftUI

/// Why a line's timetable is or is not there, in the app's own words.
///
/// The board says "this line is not in the published timetable", which is true and
/// useless on its own: the line was there last week. What changed is the archive -
/// it was republished, and it renumbers every entry when it is - so this screen
/// shows which mapping is in force, what entries it names, whether the archive
/// still holds them, and what each line's last attempt did.
struct TimetableDiagnosticsView: View {
    let timetables: LineTimetableStore
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
        .onChange(of: isRefreshingMapping) { _, refreshing in
            // The refresh is a request away, so the screen is rebuilt when it lands
            // rather than when the button was tapped.
            guard !refreshing else { return }
            diagnostics = makeDiagnostics()
        }
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
            LabeledContent("Built for") {
                Text(Self.publication(diagnostics.mappingArchive))
                    .font(.footnote)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Matches the index") {
                Text(Self.freshness(diagnostics.freshness))
                    .foregroundStyle(diagnostics.freshness.isStale ? Color.orange : Color.secondary)
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
            if diagnostics.freshness.isStale {
                Text("The mapping names entries of an older archive than the index on this phone, so every line will look \"not in the published timetable\" until it is refreshed.")
            } else {
                Text("Which archive entry holds each line. The copy inside the app goes stale every time the ministry republishes the archive - that is what makes every line look \"not in the published timetable\" at once. Refreshing downloads the mapping published at vdv.ondralinek.cz.")
            }
        }
    }

    /// What a mapping was built from, in a line a person can compare.
    private static func publication(_ archive: MappingArchive?) -> String {
        guard let archive, !archive.isEmpty else { return String(localized: "Not recorded") }
        var parts: [String] = []
        if let date = archive.date, date.count == 8 {
            let day = String(date.prefix(2)), month = String(date.dropFirst(2).prefix(2))
            parts.append("\(day). \(Int(month) ?? 0). \(date.suffix(4))")
        }
        if let bytes = archive.bytes {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        return parts.isEmpty ? String(localized: "Not recorded") : parts.joined(separator: " · ")
    }

    private static func freshness(_ freshness: MappingFreshness) -> String {
        switch freshness {
        case .current: return String(localized: "Yes")
        case .unknown: return String(localized: "Cannot be told")
        case .stale: return String(localized: "No - stale")
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
            LabeledContent("Readable lines") {
                Text(String(format: String(localized: "%lld"), diagnostics.downloaded.count))
            }

            NavigationLink {
                DownloadedLinesView(store: timetables)
            } label: {
                Label("Browse what was downloaded", systemImage: "tray.full")
            }

            ForEach(diagnostics.cacheFiles) { file in
                cacheFileRow(file)
            }
        } header: {
            Text("Downloaded lines")
        } footer: {
            Text("Every archive entry file the app keeps, the line it declares in its own tables, and the line that reads it today. A file whose declared line has no reader was cached for an archive the mapping no longer describes.")
        }
    }

    private func cacheFileRow(_ file: TimetableDiagnostics.CacheFile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: file.isInIndex ? "doc.zipper" : "doc.zipper.badge.clock")
                    .font(.caption)
                    .foregroundStyle(file.isInIndex ? Color.secondary : Color.orange)
                Text(file.name).font(.subheadline.monospaced())
                Spacer(minLength: 0)
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(file.declaredLine.map { String(format: String(localized: "declares %@"), $0) }
                     ?? String(localized: "not readable"))
                    .monospacedDigit()
                Text("·")
                Text(file.servedLine.map { String(format: String(localized: "reads %@"), $0) }
                     ?? String(localized: "no line reads it"))
                    .monospacedDigit()
                if !file.isInIndex {
                    Text("·")
                    Text("not in the index")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func linesSection(_ diagnostics: TimetableDiagnostics) -> some View {
        Section {
            let counts = diagnostics.counts
            LabeledContent("Downloaded") { Text("\(counts.downloaded)") }
            LabeledContent("Failed") { Text("\(counts.failed)") }
            LabeledContent("Not downloaded") { Text("\(counts.untouched)") }

            ForEach(visibleLines(diagnostics)) { line in
                if let readable = diagnostics.downloaded.first(where: { $0.lineNumber == line.lineNumber }) {
                    NavigationLink {
                        TimetableLineView(line: readable, store: timetables)
                    } label: {
                        row(line)
                    }
                } else {
                    row(line)
                }
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
