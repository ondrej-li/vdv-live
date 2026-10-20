import Foundation
import Observation

/// Whether the index the app holds is still the published one.
enum TimetableUpdate: Equatable {
    /// The server has not been asked in this launch.
    case unchecked
    /// The index is the published archive.
    case upToDate
    /// The server has rebuilt the archive since the index was read.
    case outdated
    /// The index does not say which archive it came from, so the two cannot be
    /// compared. This is an index stored before the version was recorded.
    case cannotTell
}

/// Keeps the timetable archive within reach of the app.
///
/// The archive is one 106 MB zip for the whole country, and a line cannot be
/// asked for by name, so the app works in two steps:
///
/// 1. **The index.** One range request reads the archive's central directory -
///    about two megabytes - and that says where every entry lives. This is the
///    download the settings screen offers.
/// 2. **A line.** The shipped mapping (see `tools/jdf_lines_mapping.py`) says
///    which entries a line has, and each one is a few kilobytes fetched by
///    range. Entries are cached on disk, so a line is only fetched once.
///
/// Every fetched entry is checked against the line number in its own `Linky.txt`
/// before it is used, because the mapping baked into the app is a snapshot and
/// the archive is rebuilt three times a week.
@MainActor
@Observable
final class LineTimetableStore {
    /// True while the index is being downloaded.
    private(set) var isDownloading = false
    /// When the index was last read from the archive.
    private(set) var downloadedAt: Date?
    private(set) var errorMessage: String?
    /// Whether the index is still the one the portal publishes, once it has been
    /// asked. See `checkForUpdates()`.
    private(set) var update: TimetableUpdate = .unchecked
    /// True while the server is being asked which archive it is offering.
    private(set) var isCheckingForUpdates = false
    /// Which publication the index was read from, when it is known.
    private var storedVersion: ArchiveVersion?
    /// Lines the shipped mapping knows about.
    let knownLineCount: Int

    /// Whether a line's timetable can be fetched at all.
    var isReady: Bool { !index.isEmpty }
    /// When the archive the index came from was published, when it said so.
    var archivePublishedAt: Date? { storedVersion?.lastModified }

    private let client: TimetableArchiveReading
    private let mapping: [String: [String]]
    private let files: TimetableFiles
    private var index: [String: ZipArchive.Entry] = [:]
    private var timetables: [String: LineTimetable] = [:]

    init(
        client: TimetableArchiveReading = HTTPTimetableArchive(),
        mapping: [String: [String]]? = nil,
        files: TimetableFiles = TimetableFiles()
    ) {
        let mapping = mapping ?? LineTimetableStore.bundledMapping()
        self.client = client
        self.mapping = mapping
        self.files = files
        self.knownLineCount = mapping.count
        self.index = files.loadIndex()
        self.downloadedAt = files.loadDownloadDate()
        self.storedVersion = files.loadVersion()
    }

    // MARK: - The index

    /// Reads the archive's central directory and keeps it for next time.
    func downloadIndex() async {
        guard !isDownloading else { return }
        isDownloading = true
        errorMessage = nil
        defer { isDownloading = false }

        do {
            let entries = try await client.entries()
            index = Dictionary(entries.map { ($0.name, $0) }) { first, _ in first }
            timetables.removeAll()
            let now = Date()
            downloadedAt = now
            files.saveIndex(entries, date: now)
            // Which archive this index came from, so that the next launch can
            // say whether it is still the published one.
            await recordVersion()
            update = storedVersion == nil ? .cannotTell : .upToDate
        } catch {
            errorMessage = (error as? TimetableError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Forgets the index and everything cached from it.
    func forgetIndex() {
        index.removeAll()
        timetables.removeAll()
        downloadedAt = nil
        errorMessage = nil
        storedVersion = nil
        update = .unchecked
        files.removeAll()
    }

    // MARK: - Is this index still current?

    /// Records which archive the index that is now on disk came from.
    ///
    /// A failure here is not a failed download: the index is read and usable, and
    /// the only thing lost is the ability to say later whether it is still the
    /// published one, which `update` then reports as `.cannotTell`.
    private func recordVersion() async {
        do {
            let version = try await client.version()
            storedVersion = version
            files.saveVersion(version)
        } catch {
            storedVersion = nil
            files.removeVersion()
        }
    }

    /// Asks the portal which archive it is offering and compares it with the one
    /// the index was read from.
    ///
    /// One range request and no download: the answer is in the response's
    /// headers.
    func checkForUpdates() async {
        guard isReady, !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        errorMessage = nil
        defer { isCheckingForUpdates = false }

        do {
            let published = try await client.version()
            guard let stored = storedVersion else {
                // Stored before the version was recorded: nothing to compare it
                // with, and calling it current would be a guess.
                update = .cannotTell
                return
            }
            update = stored.describesSamePublication(as: published) ? .upToDate : .outdated
        } catch {
            errorMessage = (error as? TimetableError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - One line

    /// The published timetable of a line.
    ///
    /// - Parameter serviceNumber: the run the vehicle is on (`Spoj`). When it is
    ///   known, the entry that actually contains that run is the one fetched.
    /// - Returns: `nil` when the line is not in the mapping at all, which is the
    ///   answer for anything outside the region this app covers.
    func timetable(forLine lineNumber: String, serviceNumber: String? = nil) async throws -> LineTimetable? {
        if let cached = timetables[lineNumber] {
            return cached
        }
        guard isReady else { throw TimetableError.notDownloaded }
        guard let candidates = mapping[lineNumber], !candidates.isEmpty else { return nil }

        var fallback: LineTimetable?
        for name in candidates {
            guard let entry = index[name] else { continue }
            let timetable = try await timetable(of: entry)

            // The mapping is a snapshot; the archive is rebuilt three times a
            // week. A mismatch means the entry now holds another line.
            guard timetable.lineNumber == lineNumber else { continue }

            if serviceNumber == nil || timetable.run(serviceNumber: serviceNumber) != nil {
                timetables[lineNumber] = timetable
                return timetable
            }
            fallback = fallback ?? timetable
        }

        guard let fallback else {
            throw TimetableError.lineNotInArchive(lineNumber)
        }
        timetables[lineNumber] = fallback
        return fallback
    }

    private func timetable(of entry: ZipArchive.Entry) async throws -> LineTimetable {        let inner = try await files.entryArchive(entry) {            try await client.contents(of: entry)
        }
        let contents = try ZipArchive.entries(in: inner)
        var files: [String: Data] = [:]
        for file in contents {
            files[file.name] = try? ZipArchive.contents(of: file, in: inner)
        }
        return try JDFTimetableParser.parse(files: files)
    }

    // MARK: - Coverage of the region

    /// Every line the shipped mapping knows about, in the order a person reads.
    ///
    /// This is what "cross-check the whole region" means: 381 lines, once the index
    /// has been downloaded.
    var knownLines: [String] {
        mapping.keys.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    /// Timetables already fetched this session, which is everything a cross-check
    /// can work from without asking the network.
    var cachedTimetables: [LineTimetable] {
        timetables.values.sorted { $0.lineNumber < $1.lineNumber }
    }

    /// How many of the mapping's lines have a timetable in memory.
    var coveredLineCount: Int { timetables.count }

    /// True while the region's lines are being fetched in the background.
    private(set) var isPrefetching = false

    /// Fetches the timetable of every line the mapping knows.
    ///
    /// One range request per line, a few kilobytes each, cached on disk and reused
    /// by every launch after this one - so a phone that has done this once works
    /// offline from then on. Deliberately sequential: the archive is a ministry
    /// portal, and the point of this pass is coverage rather than speed.
    ///
    /// - Parameter onLineCached: called on the main actor after each line, so the
    ///   map can show what it has while the rest is still arriving.
    func prefetchKnownLines(onLineCached: (() -> Void)? = nil) async {
        guard isReady, !isPrefetching else { return }
        isPrefetching = true
        defer { isPrefetching = false }

        var consecutiveFailures = 0
        for line in knownLines {
            if Task.isCancelled { return }
            guard timetables[line] == nil else { continue }
            do {
                _ = try await timetable(forLine: line)
                consecutiveFailures = 0
                onLineCached?()
            } catch TimetableError.lineNotInArchive(_) {
                // The mapping is a snapshot and the archive is rebuilt three times
                // a week, so a line that has moved is expected rather than a sign
                // that the portal is unreachable.
                consecutiveFailures = 0
            } catch {
                consecutiveFailures += 1
                // Something is wrong with the connection rather than with a line:
                // three hundred more failures would only cost battery.
                if consecutiveFailures >= 3 { return }
            }
            // Between two fetches the map gets a frame, and so does the next
            // refresh: this pass must not be something the user can feel.
            await Task.yield()
        }
    }

    // MARK: - The shipped mapping

    /// The line to archive entry mapping that ships with the app.
    static func bundledMapping(in bundle: Bundle = .main) -> [String: [String]] {
        guard let url = bundle.url(forResource: "jdf-lines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(MappingDocument.self, from: data) else {
            return [:]
        }
        return document.lines
    }

    private struct MappingDocument: Decodable {
        let lines: [String: [String]]
    }
}

/// Files the store keeps: the archive index and the entries fetched from it.
struct TimetableFiles: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("timetables", isDirectory: true)
        }
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private var dateURL: URL { directory.appendingPathComponent("index-date.txt") }
    private var versionURL: URL { directory.appendingPathComponent("index-version.json") }

    func loadIndex() -> [String: ZipArchive.Entry] {
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder().decode([StoredEntry].self, from: data) else {
            return [:]
        }
        return Dictionary(stored.map { ($0.name, $0.entry) }) { first, _ in first }
    }

    func loadDownloadDate() -> Date? {
        guard let text = try? String(contentsOf: dateURL, encoding: .utf8) else { return nil }
        return ISO8601DateFormatter().date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func saveIndex(_ entries: [ZipArchive.Entry], date: Date) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stored = entries.map(StoredEntry.init)
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: indexURL, options: .atomic)
        }
        let text = ISO8601DateFormatter().string(from: date)
        try? text.write(to: dateURL, atomically: true, encoding: .utf8)
    }

    /// The archive the index on disk was read from, when it was recorded.
    func loadVersion() -> ArchiveVersion? {
        guard let data = try? Data(contentsOf: versionURL) else { return nil }
        return try? JSONDecoder().decode(ArchiveVersion.self, from: data)
    }

    func saveVersion(_ version: ArchiveVersion) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(version) else { return }
        try? data.write(to: versionURL, options: .atomic)
    }

    func removeVersion() {
        try? FileManager.default.removeItem(at: versionURL)
    }

    /// The entry's own zip. Small - a few kilobytes - and reused, so a line is
    /// fetched once and then works offline.
    func entryArchive(
        _ entry: ZipArchive.Entry,
        fetch: () async throws -> Data
    ) async throws -> Data {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("entry-\(entry.name)")
        if let cached = try? Data(contentsOf: url), !cached.isEmpty {
            return cached
        }
        let data = try await fetch()
        try? data.write(to: url, options: .atomic)
        return data
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private struct StoredEntry: Codable {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int

        init(_ entry: ZipArchive.Entry) {
            name = entry.name
            method = entry.method
            compressedSize = entry.compressedSize
            uncompressedSize = entry.uncompressedSize
            localHeaderOffset = entry.localHeaderOffset
        }

        var entry: ZipArchive.Entry {
            ZipArchive.Entry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            )
        }
    }
}
