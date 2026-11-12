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
    /// Lines the mapping knows about.
    var knownLineCount: Int { mapping.count }
    /// Where the mapping in force came from.
    private(set) var mappingSource: TimetableDiagnostics.MappingSource = .bundled
    /// True while a fresher mapping is being fetched.
    private(set) var isRefreshingMapping = false
    /// Why the last refresh did not happen, when it did not.
    private(set) var mappingErrorMessage: String?

    /// Whether a line's timetable can be fetched at all.
    var isReady: Bool { !index.isEmpty }
    /// When the archive the index came from was published, when it said so.
    var archivePublishedAt: Date? { storedVersion?.lastModified }

    private let client: TimetableArchiveReading
    private let mappingFetcher: TimetableMappingFetching
    private let mappingFiles: TimetableMappingFiles
    private let files: TimetableFiles
    private var mapping: [String: [String]]
    /// Which archive the mapping was built from, when the document says.
    private(set) var mappingArchive: MappingArchive?
    private var index: [String: ZipArchive.Entry] = [:]
    private var timetables: [String: LineTimetable] = [:]
    /// The last thing each line did, kept on disk so the screen can explain itself
    /// long after the session that saw it.
    private var lineRecords: [String: TimetableLineRecord] = [:]
    /// A refresh is tried once per line that cannot be resolved, and once per
    /// session at most through this flag - a mapping that is already current must
    /// not be asked for again on every tap.
    private var hasTriedRefresh = false
    /// Whether the launch-time check has already fetched a mapping because the one
    /// in force was older than the index. Separate from ``hasTriedRefresh``: this one
    /// runs before any line has failed, and must not use up the recovery a later
    /// failure needs.
    private var hasTriedAutomaticRefresh = false

    init(
        client: TimetableArchiveReading = HTTPTimetableArchive(),
        mapping: [String: [String]]? = nil,
        files: TimetableFiles = TimetableFiles(),
        mappingFetcher: TimetableMappingFetching = HTTPTimetableMapping(),
        mappingFiles: TimetableMappingFiles = TimetableMappingFiles()
    ) {
        self.client = client
        self.mappingFetcher = mappingFetcher
        self.mappingFiles = mappingFiles
        self.files = files
        self.index = files.loadIndex()
        self.downloadedAt = files.loadDownloadDate()
        self.storedVersion = files.loadVersion()
        self.lineRecords = files.loadLineRecords()

        if let mapping {
            self.mapping = mapping
            self.mappingSource = .bundled
        } else if let data = mappingFiles.load(),
                  let published = TimetableMappingDocument.read(data) {
            // A copy fetched from the project's site outranks the one in the app:
            // the bundle cannot know that the archive was republished on Monday.
            self.mapping = published.lines
            self.mappingArchive = published.archive
            self.mappingSource = .published(mappingFiles.modifiedAt() ?? Date())
        } else {
            let bundled = LineTimetableStore.bundledMappingDocument()
            self.mapping = bundled.lines
            self.mappingArchive = bundled.archive
            self.mappingSource = .bundled
        }
    }

    /// Whether the mapping in force could have been built from the archive the index
    /// was read from.
    ///
    /// `unknown` when the index has not been read or neither side carries an
    /// identity: a mapping that cannot be shown to be stale is not called stale.
    var mappingFreshness: MappingFreshness {
        guard let mappingArchive, !mappingArchive.isEmpty, let storedVersion else { return .unknown }
        return .between(mapping: mappingArchive, index: storedVersion)
    }

    /// Refreshes the mapping when it is provably older than the index.
    ///
    /// Called after the index is read and when the screen opens: a republication
    /// renumbers every entry, so a mapping that lags behind the index is not a
    /// partial failure - it is every line failing at once, which is exactly what a
    /// reader sees as "not in the published timetable" on a phone that was fine
    /// yesterday. One request, once per launch.
    ///
    /// - Returns: whether a refresh was attempted.
    @discardableResult
    func refreshMappingIfStale() async -> Bool {
        // Only a mapping that can be *shown* to be older is fetched again: a mapping
        // written before the builder recorded its archive cannot be compared with
        // anything, and is left to the recovery below (a line that fails refreshes
        // it) rather than costing a request on every launch.
        guard mappingFreshness.isStale, !hasTriedAutomaticRefresh else { return false }
        hasTriedAutomaticRefresh = true
        return await refreshMapping()
    }

    // MARK: - The line mapping

    /// Fetches the mapping the project publishes for the current archive.
    ///
    /// - Returns: whether a fresher mapping is now in force.
    @discardableResult
    func refreshMapping() async -> Bool {
        guard !isRefreshingMapping else { return false }
        isRefreshingMapping = true
        mappingErrorMessage = nil
        defer { isRefreshingMapping = false }

        do {
            let data = try await mappingFetcher.latestMapping()
            guard let published = TimetableMappingDocument.read(data) else {
                mappingErrorMessage = String(localized: "The published mapping could not be read.")
                return false
            }
            mappingFiles.save(data)
            mapping = published.lines
            mappingArchive = published.archive
            mappingSource = .published(Date())
            // Every parsed timetable was read through the old mapping, and the
            // archive does not change - only which entry holds which line does.
            timetables.removeAll()
            SharedContainer.reloadWidgets()
            return true
        } catch {
            mappingErrorMessage = (error as? TimetableError)?.errorDescription
                ?? error.localizedDescription
            return false
        }
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
            // The index has just replaced the one the mapping was built for, so
            // check the two agree before a single line is asked for.
            await refreshMappingIfStale()
            // A board widget could not be built before this index existed; it can now.
            SharedContainer.reloadWidgets()
        } catch {
            errorMessage = (error as? TimetableError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Forgets the index and everything cached from it.
    func forgetIndex() {
        index.removeAll()
        timetables.removeAll()
        lineRecords.removeAll()
        downloadedAt = nil
        errorMessage = nil
        storedVersion = nil
        update = .unchecked
        hasTriedRefresh = false
        hasTriedAutomaticRefresh = false
        files.removeAll()
    }

    // MARK: - What the screen can say about itself

    /// The archive, the mapping, the cache and every line's last attempt.
    ///
    /// Built on demand rather than kept in sync: it reads the index in memory, the
    /// files on disk and the records, so it describes the device rather than this
    /// session - which is what answers "why did it say the line is not published".
    func diagnostics() -> TimetableDiagnostics {
        let filesOnDisk = files.cachedEntryFiles()
        let onDisk = Set(filesOnDisk.map(\.name))

        // Which line reads which file today, from the records the app wrote when it
        // did, so a file can be shown against the line it serves rather than only
        // against the name the archive happened to give it.
        let servedBy: [String: String] = lineRecords.reduce(into: [:]) { result, pair in
            guard pair.value.failure == nil, let entry = pair.value.entryName else { return }
            result[entry] = pair.key
        }

        let lines = mapping.keys
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
            .map { line in
                let candidates = (mapping[line] ?? []).map { name in
                    TimetableDiagnostics.Candidate(entryName: name,
                                                   isInIndex: index[name] != nil,
                                                   isOnDisk: onDisk.contains(name))
                }
                return TimetableDiagnostics.Line(lineNumber: line,
                                                 record: lineRecords[line],
                                                 candidates: candidates,
                                                 isInMemory: timetables[line] != nil)
            }

        let readable = downloadedTimetables()

        let cacheFiles = filesOnDisk.map { file in
            TimetableDiagnostics.CacheFile(
                name: file.name,
                bytes: file.bytes,
                modifiedAt: file.modifiedAt,
                declaredLine: declaredLine(ofEntryNamed: file.name),
                servedLine: servedBy[file.name],
                isInIndex: index[file.name] != nil
            )
        }

        return TimetableDiagnostics(
            archive: .init(entryCount: index.count,
                           publishedAt: storedVersion?.lastModified,
                           downloadedAt: downloadedAt,
                           etag: storedVersion?.etag),
            mapping: .init(lineCount: mapping.count, source: mappingSource),
            mappingArchive: mappingArchive,
            freshness: mappingFreshness,
            cacheEntryCount: onDisk.count,
            cacheBytes: files.cachedBytes(),
            cacheFiles: cacheFiles,
            lines: lines,
            downloaded: readable
        )
    }

    /// The line an entry file on disk declares, read out of its own `Linky.txt`.
    func declaredLine(ofEntryNamed name: String) -> String? {
        guard let data = files.cachedEntryData(named: name),
              let contents = try? ZipArchive.entries(in: data),
              let linky = contents.first(where: { $0.name == "Linky.txt" }),
              let table = try? ZipArchive.contents(of: linky, in: data) else { return nil }
        return JDFTimetableParser.lineNumber(inLinky: table)
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

        do {
            if let timetable = try await resolve(lineNumber: lineNumber, serviceNumber: serviceNumber) {
                return timetable
            }
            return nil
        } catch let error as TimetableError {
            // A line the mapping cannot resolve may simply have moved: the archive
            // is republished three times a week and renumbers every entry, which
            // leaves the mapping in the app naming entries that now hold other
            // lines. Ask once for the mapping the project publishes, then try the
            // same line again with it.
            if case .lineNotInArchive = error, !hasTriedRefresh {
                hasTriedRefresh = true
                if await refreshMapping() {
                    return try await timetable(forLine: lineNumber, serviceNumber: serviceNumber)
                }
            }
            remember(.failed(line: lineNumber,
                             reason: error.errorDescription ?? String(describing: error),
                             at: Date()),
                     for: lineNumber)
            throw error
        }
    }

    /// A candidate entry that really does hold the line being asked for.
    struct ResolvedEntry {
        let timetable: LineTimetable
        let entryName: String
        /// True when this came from a file cached for an earlier publication, which
        /// the current archive no longer has under that name.
        let isFromEarlierArchive: Bool
    }

    /// The line's timetable through the mapping in force, or `nil` when the mapping
    /// does not name the line at all - which is the answer for anything outside the
    /// region this app covers.
    ///
    /// A line is published as several entries - one per validity period, with its
    /// own calendar exceptions - and the mapping lists them all without saying which
    /// is current. Every candidate is therefore read and the entries verified by
    /// their own `Linky.txt`; the newest period that covers today is the one that
    /// answers, and the real `Spoj` when a run was named.
    private func resolve(lineNumber: String, serviceNumber: String?) async throws -> LineTimetable? {
        guard let candidates = mapping[lineNumber], !candidates.isEmpty else { return nil }

        var resolved: [ResolvedEntry] = []

        for name in candidates {
            guard let entry = index[name] else {
                // Not in this archive: what is on disk may still be the line's
                // timetable, from the publication the mapping was built for.
                if let cached = cachedEntry(named: name, forLine: lineNumber) {
                    resolved.append(ResolvedEntry(timetable: cached,
                                                  entryName: name,
                                                  isFromEarlierArchive: true))
                }
                continue
            }

            var parsed = try? await timetable(of: entry)
            if parsed?.lineNumber != lineNumber {
                // Either the entry now holds another line - the mapping is a
                // snapshot and the archive renumbers its entries - or the file on
                // disk was cached from an earlier publication under a name that has
                // since been reused. Ask the archive once, by the entry's current
                // identity, before believing the mismatch.
                parsed = try? await timetable(of: entry, refreshing: true)
            }
            guard let parsed, parsed.lineNumber == lineNumber else { continue }
            resolved.append(ResolvedEntry(timetable: parsed,
                                          entryName: entry.name,
                                          isFromEarlierArchive: false))
        }

        guard let chosen = Self.choose(resolved, serviceNumber: serviceNumber, today: ServiceDay(date: Date(), in: ExpectedServices.regionTimeZone)) else {
            throw TimetableError.lineNotInArchive(lineNumber)
        }

        timetables[lineNumber] = chosen.timetable
        remember(.downloaded(line: lineNumber,
                             entry: chosen.entryName,
                             declared: chosen.timetable.lineNumber,
                             fromEarlierArchive: chosen.isFromEarlierArchive,
                             at: Date()),
                 for: lineNumber)
        return chosen.timetable
    }

    /// The candidate that answers best: the one holding the run asked for, then the
    /// newest validity period that covers today, then a current copy over a cached
    /// one.
    static func choose(_ resolved: [ResolvedEntry],
                       serviceNumber: String?,
                       today: ServiceDay) -> ResolvedEntry? {
        resolved
            .filter { serviceNumber == nil || $0.timetable.run(serviceNumber: serviceNumber) != nil }
            .max { lhs, rhs in
                let left = rank(lhs, today: today)
                let right = rank(rhs, today: today)
                return left.lexicographicallyPrecedes(right)
            }
    }

    /// How good a candidate is, compared left to right: whether its newest period has
    /// started, how recently that period started, and whether it is a copy the current
    /// archive still holds.
    private static func rank(_ entry: ResolvedEntry, today: ServiceDay) -> [Int] {
        let starts = entry.timetable.validity.map(\.from.number).sorted()
        let started = starts.filter { $0 <= today.number }
        return [
            started.isEmpty ? 0 : 1,
            started.last ?? Int.min,
            entry.isFromEarlierArchive ? 0 : 1
        ]
    }

    /// Keeps what a line's last attempt did, for the diagnostics screen.
    private func remember(_ record: TimetableLineRecord, for line: String) {
        lineRecords[line] = record
        files.saveLineRecords(lineRecords)
    }

    private func timetable(of entry: ZipArchive.Entry,
                           refreshing: Bool = false) async throws -> LineTimetable {
        let inner = try await files.entryArchive(entry, refreshing: refreshing) {
            try await client.contents(of: entry)
        }
        return try Self.parse(entryArchive: inner)
    }

    /// The tables inside one entry, keyed by their JDF names.
    private static func parse(entryArchive inner: Data) throws -> LineTimetable {
        let contents = try ZipArchive.entries(in: inner)
        var files: [String: Data] = [:]
        for file in contents {
            files[file.name] = try? ZipArchive.contents(of: file, in: inner)
        }
        return try JDFTimetableParser.parse(files: files)
    }

    /// A line read out of an entry file cached for an earlier publication.
    ///
    /// The archive renumbers its entries when it is republished, so a file on disk
    /// can be the only copy of a line's timetable the phone has - and a timetable a
    /// few days old is a great deal better than "not in the published timetable".
    private func cachedEntry(named name: String, forLine lineNumber: String) -> LineTimetable? {
        guard let data = files.cachedEntryData(named: name),
              let timetable = try? Self.parse(entryArchive: data),
              timetable.lineNumber == lineNumber else {
            return nil
        }
        return timetable
    }

    // MARK: - What is on this phone

    /// The lines whose timetables can be read without the network, newest first by
    /// line number, with the archive entry each came from.
    ///
    /// Reads what is in memory and what is on disk, and never asks the archive: this
    /// is what the browse screen shows, and a screen that listed the whole region
    /// would be a screen that downloaded it.
    func downloadedTimetables() -> [DownloadedTimetable] {
        var result: [DownloadedTimetable] = []

        for line in knownLines {
            if let timetable = timetables[line] {
                let entryName = lineRecords[line]?.entryName ?? timetable.lineNumber
                result.append(DownloadedTimetable(
                    lineNumber: line,
                    timetable: timetable,
                    entryName: entryName,
                    isFromEarlierArchive: lineRecords[line]?.isFromEarlierArchive ?? false,
                    sourceFiles: sourceFiles(ofEntryNamed: entryName)
                ))
                continue
            }
            guard let record = lineRecords[line],
                  record.failure == nil,
                  let entryName = record.entryName,
                  let data = files.cachedEntryData(named: entryName),
                  let timetable = try? Self.parse(entryArchive: data),
                  timetable.lineNumber == line else { continue }

            result.append(DownloadedTimetable(
                lineNumber: line,
                timetable: timetable,
                entryName: entryName,
                isFromEarlierArchive: record.isFromEarlierArchive ?? false,
                sourceFiles: sourceFiles(ofEntryNamed: entryName)
            ))
        }

        return result
    }

    /// The entry files on disk, as the file system holds them.
    var cachedEntryFiles: [CachedEntryFile] { files.cachedEntryFiles() }

    /// The JDF tables inside one entry file, as the archive packed them.
    func sourceFiles(ofEntryNamed name: String) -> [TimetableSourceFile] {
        guard let data = files.cachedEntryData(named: name),
              let contents = try? ZipArchive.entries(in: data) else { return [] }
        return contents
            .map { TimetableSourceFile(name: $0.name, bytes: $0.uncompressedSize) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// One table of an entry, decoded, for the reader who wants to see the source.
    ///
    /// JDF is CP1250 with semicolon-separated, quoted fields; this hands the text
    /// over as it is rather than reshaping it, because the point is to show what
    /// arrived.
    func sourceText(ofEntryNamed name: String, file: String) -> String? {
        guard let data = files.cachedEntryData(named: name),
              let contents = try? ZipArchive.entries(in: data),
              let entry = contents.first(where: { $0.name == file }),
              let inner = try? ZipArchive.contents(of: entry, in: data) else { return nil }
        return String(data: inner, encoding: .windowsCP1250)
            ?? String(data: inner, encoding: .utf8)
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

    /// The line to archive entry mapping that ships with the app, identity and all.
    static func bundledMappingDocument(in bundle: Bundle = .main) -> TimetableMappingDocument {
        guard let url = bundle.url(forResource: "jdf-lines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = TimetableMappingDocument.read(data, minimumLines: 1) else {
            return TimetableMappingDocument(lines: [:], archive: nil)
        }
        return document
    }

    /// The mapping itself, for callers that do not care which archive it is for.
    static func bundledMapping(in bundle: Bundle = .main) -> [String: [String]] {
        bundledMappingDocument(in: bundle).lines
    }
}

/// Files the store keeps: the archive index and the entries fetched from it.
struct TimetableFiles: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? SharedContainer.timetableDirectory
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private var dateURL: URL { directory.appendingPathComponent("index-date.txt") }
    private var versionURL: URL { directory.appendingPathComponent("index-version.json") }
    private var recordsURL: URL { directory.appendingPathComponent("lines.json") }

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
        refreshing: Bool = false,
        fetch: () async throws -> Data
    ) async throws -> Data {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = entryURL(named: entry.name)
        if !refreshing, let cached = try? Data(contentsOf: url), !cached.isEmpty {
            return cached
        }
        let data = try await fetch()
        try? data.write(to: url, options: .atomic)
        return data
    }

    /// The entry file on disk, `nil` when it was never fetched or has been removed.
    func cachedEntryData(named name: String) -> Data? {
        guard let data = try? Data(contentsOf: entryURL(named: name)), !data.isEmpty else {
            return nil
        }
        return data
    }

    func entryURL(named name: String) -> URL {
        directory.appendingPathComponent("entry-\(name)")
    }

    /// Every entry file on disk, with what the file system says about it.
    func cachedEntryFiles() -> [CachedEntryFile] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.hasPrefix("entry-") }
            .compactMap { file in
                let url = directory.appendingPathComponent(file)
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                guard let size = attributes?[.size] as? Int else { return nil }
                return CachedEntryFile(name: String(file.dropFirst("entry-".count)),
                                       bytes: size,
                                       modifiedAt: attributes?[.modificationDate] as? Date)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func removeEntry(named name: String) {
        try? FileManager.default.removeItem(at: entryURL(named: name))
    }

    /// What each line's last attempt did, keyed by line number.
    func loadLineRecords() -> [String: TimetableLineRecord] {
        guard let data = try? Data(contentsOf: recordsURL),
              let records = try? JSONDecoder().decode([String: TimetableLineRecord].self, from: data) else {
            return [:]
        }
        return records
    }

    func saveLineRecords(_ records: [String: TimetableLineRecord]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: recordsURL, options: .atomic)
    }

    /// The entry files on disk, by the name the archive knows them under.
    ///
    /// The cache is keyed by entry name rather than by line, because that is what
    /// has to be fetched; which line an entry holds is a property of the archive
    /// that day, and is what the records remember.
    func cachedEntryNames() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("entry-") }
                        .map { String($0.dropFirst("entry-".count)) })
    }

    func cachedBytes() -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.reduce(0) { total, name in
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(name).path
            )
            return total + ((attributes?[.size] as? Int) ?? 0)
        }
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
