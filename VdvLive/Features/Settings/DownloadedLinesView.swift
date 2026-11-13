import SwiftUI

/// What is actually on the phone: the lines whose timetables were downloaded, read
/// back out of the files rather than described from a summary.
///
/// The timetables screen was a set of counters, and a counter cannot be argued with:
/// it said six files were cached while every line claimed to be missing. This screen
/// answers the question a reader actually has - *what did this app download, and what
/// does it say?* - by showing the entries on disk, the line each declares, and the
/// parsed timetable behind it, down to the JDF tables themselves.
struct DownloadedLinesView: View {
    let store: LineTimetableStore

    @State private var lines: [DownloadedTimetable] = []
    @State private var files: [CachedEntryFile] = []
    @State private var declaredLines: [String: String] = [:]
    @State private var query = ""
    @State private var isLoading = true

    private var matches: [DownloadedTimetable] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return lines }
        return lines.filter { line in
            line.lineNumber.contains(trimmed)
                || line.timetable.routeName.localizedCaseInsensitiveContains(trimmed)
                || line.displayNumber == trimmed
        }
    }

    var body: some View {
        List {
            if isLoading {
                ProgressView()
            } else if lines.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No line is on this phone yet", systemImage: "tray")
                    } description: {
                        Text("A line is downloaded the first time something needs it: a vehicle's card, a stop's board, or the setting that fills in lines the feed leaves out.")
                    }
                }
            } else {
                Section {
                    ForEach(matches) { line in
                        NavigationLink {
                            TimetableLineView(line: line, store: store, siblings: matches)
                        } label: {
                            row(line)
                        }
                    }
                } header: {
                    Text("Lines")
                } footer: {
                    Text("One row per line whose timetable can be read without the network.")
                }
            }

            if !files.isEmpty {
                Section {
                    ForEach(files) { file in
                        fileRow(file)
                    }
                } header: {
                    Text("Files on disk")
                } footer: {
                    Text("The archive entry each line was read out of. The ministry renumbers these names every time it republishes, so a file can declare a different line than the one it was downloaded for.")
                }
            }
        }
        .navigationTitle("Downloaded lines")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Line or route"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ line: DownloadedTimetable) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(line.displayNumber)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if line.isFromEarlierArchive {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                Text(String(format: String(localized: "%lld runs"), line.runs.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(line.timetable.routeName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 6) {
                Text(String(format: String(localized: "%lld stops"), line.stopCount))
                if let span = line.spanText {
                    Text("·")
                    Text(span)
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func fileRow(_ file: CachedEntryFile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "doc.zipper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(file.name)
                    .font(.subheadline.monospaced())
                Spacer(minLength: 0)
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if let declared = declaredLines[file.name] {
                    Text(String(format: String(localized: "declares %@"), declared))
                        .monospacedDigit()
                } else {
                    Text("not readable")
                }
                if let date = file.modifiedAt {
                    Text("·")
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        isLoading = lines.isEmpty
        defer { isLoading = false }
        lines = store.downloadedTimetables()
        files = store.cachedEntryFiles
        declaredLines = files.reduce(into: [:]) { result, file in
            result[file.name] = store.declaredLine(ofEntryNamed: file.name)
        }
    }
}

/// One downloaded line: what the timetable says, where it came from, and the files
/// it was read out of.
struct TimetableLineView: View {
    let line: DownloadedTimetable
    let store: LineTimetableStore
    /// The other lines on the list this one was opened from, so the next can be
    /// reached without going back - which is how a reader compares two lines.
    var siblings: [DownloadedTimetable] = []

    /// The line after this one on the list it came from.
    private var nextLine: DownloadedTimetable? {
        guard let index = siblings.firstIndex(where: { $0.id == line.id }),
              siblings.indices.contains(index + 1) else { return nil }
        return siblings[index + 1]
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Line") {
                    HStack(spacing: 6) {
                        Text(line.displayNumber).monospacedDigit()
                        Text(line.timetable.lineNumber)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Route") {
                    Text(line.timetable.routeName)
                        .multilineTextAlignment(.trailing)
                }
                if let operatorName = line.timetable.operatorName {
                    LabeledContent("Operator") { Text(operatorName) }
                }
                if let validity = line.validityText {
                    LabeledContent("Valid") { Text(validity) }
                }
                LabeledContent("Runs") {
                    Text(String(format: String(localized: "%lld"), line.runs.count))
                }
                LabeledContent("Stops") {
                    Text(String(format: String(localized: "%lld"), line.stopCount))
                }
                if let span = line.spanText {
                    LabeledContent("Departs") {
                        Text(span).monospacedDigit()
                    }
                }
                LabeledContent("Archive entry") {
                    Text(line.entryName).font(.caption.monospaced())
                }
            } header: {
                Text("Timetable")
            } footer: {
                if line.isFromEarlierArchive {
                    Text("This copy came from an earlier publication of the archive: the entry it lives in has since been renumbered, so it is read from the file cached on this phone. It is still a timetable, but it may have been replaced.")
                }
            }

            Section {
                ForEach(line.sourceFiles) { file in
                    NavigationLink {
                        TimetableSourceFileView(entryName: line.entryName,
                                                file: file,
                                                store: store)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name).font(.subheadline.monospaced())
                                Text(file.purpose)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes),
                                                           countStyle: .file))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Source files")
            } footer: {
                Text("The JDF tables inside the archive entry, exactly as the ministry published them.")
            }

            Section {
                ForEach(line.runs) { run in
                    NavigationLink {
                        TimetableRunView(line: line, run: run)
                    } label: {
                        runRow(run)
                    }
                }
            } header: {
                Text("Runs")
            } footer: {
                Text("One row per service of the line, in the order they leave the first stop.")
            }

            if let nextLine {
                Section {
                    NavigationLink {
                        TimetableLineView(line: nextLine, store: store, siblings: siblings)
                    } label: {
                        Label {
                            Text(String(format: String(localized: "Line %@"), nextLine.displayNumber))
                        } icon: {
                            Image(systemName: "chevron.forward.circle")
                        }
                    }
                } footer: {
                    Text("The next line on the list, so the lines can be read one after another.")
                }
            }
        }
        .navigationTitle(Text("Line \(line.displayNumber)"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runRow(_ run: ScheduledRun) -> some View {
        let times = run.timedCalls
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(String(format: String(localized: "Run %@"), run.serviceNumber))
                    .font(.subheadline.monospacedDigit())
                Spacer(minLength: 0)
                if let first = times.first?.time, let last = times.last?.time {
                    Text("\(first.text) – \(last.text)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text(String(format: String(localized: "%lld stops"), run.calls.count))
                if let destination = run.calls.last?.stopName {
                    Text("·")
                    Text(destination).lineLimit(1).truncationMode(.tail)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The stops of one run, with the times the timetable prints.
struct TimetableRunView: View {
    let line: DownloadedTimetable
    let run: ScheduledRun

    var body: some View {
        List {
            Section {
                ForEach(run.calls) { call in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(call.stopName)
                                .font(.subheadline)
                            if !call.isServed {
                                Text("This run does not serve this stop")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(call.departure?.text ?? call.arrival?.text ?? "—")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(call.hasTime ? Color.primary : Color.secondary)
                            if call.departure != nil, let arrival = call.arrival, arrival != call.departure {
                                Text(arrival.text)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text("A stop with no time is a request stop, which the timetable marks with a symbol rather than a time.")
            }
        }
        .navigationTitle(Text("Run \(run.serviceNumber)"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One JDF table, as text.
struct TimetableSourceFileView: View {
    let entryName: String
    let file: TimetableSourceFile
    let store: LineTimetableStore

    @State private var text: String?

    var body: some View {
        ScrollView {
            if let text {
                Text(text.isEmpty ? String(localized: "(empty)") : text)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                ProgressView().padding()
            }
        }
        .navigationTitle(Text(file.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel(Text("Copy"))
                .disabled(text?.isEmpty ?? true)
            }
        }
        .task {
            guard text == nil else { return }
            text = store.sourceText(ofEntryNamed: entryName, file: file.name) ?? ""
        }
    }
}
