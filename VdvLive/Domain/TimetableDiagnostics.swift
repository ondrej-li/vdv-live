import Foundation

/// What happened the last time a line's timetable was asked for.
///
/// Kept on disk rather than in memory: the interesting failures happen on a phone
/// that has been in a pocket for a day, and by the time its owner opens the
/// timetables screen the session that saw them is gone.
struct TimetableLineRecord: Codable, Equatable, Sendable, Identifiable {
    let lineNumber: String
    /// The archive entry the timetable came from, when one did.
    let entryName: String?
    /// The line number the entry declares inside its own `Linky.txt`, which is what
    /// the app checks the mapping against before it trusts a timetable.
    let declaredLineNumber: String?
    let fetchedAt: Date
    /// Why it failed, in the words the app would show, when it did.
    let failure: String?
    /// True when the timetable came from a file cached for an earlier publication
    /// of the archive, rather than from the one the index was read from. Optional,
    /// so a record written before this was known still reads back.
    var isFromEarlierArchive: Bool?

    var id: String { lineNumber }
    var isDownloaded: Bool { failure == nil && entryName != nil }

    static func downloaded(line: String,
                           entry: String,
                           declared: String,
                           fromEarlierArchive: Bool = false,
                           at date: Date) -> TimetableLineRecord {
        TimetableLineRecord(lineNumber: line,
                            entryName: entry,
                            declaredLineNumber: declared,
                            fetchedAt: date,
                            failure: nil,
                            isFromEarlierArchive: fromEarlierArchive)
    }

    static func failed(line: String, reason: String, at date: Date) -> TimetableLineRecord {
        TimetableLineRecord(lineNumber: line,
                            entryName: nil,
                            declaredLineNumber: nil,
                            fetchedAt: date,
                            failure: reason,
                            isFromEarlierArchive: nil)
    }
}

/// One entry file the app has downloaded, as the file system holds it.
///
/// Reported rather than hidden because the cache is keyed by the archive's own
/// entry names, and those are renumbered on every republication: a file on disk can
/// belong to a line the current mapping no longer points at, which is exactly the
/// kind of thing "it says the line is not published" needs to be answered with.
struct CachedEntryFile: Equatable, Sendable, Identifiable {
    /// The entry's name in the archive, `6934.zip`.
    let name: String
    let bytes: Int
    let modifiedAt: Date?

    var id: String { name }
}

/// What the timetables screen can say about itself.
///
/// Built from what the app already holds - the index it read, the mapping it is
/// using, the files on disk and the record of each line's last attempt - so that
/// "line not in the published timetable" can be answered rather than guessed at:
/// which mapping was in force, which entries it named, whether the archive still
/// has those entries, and what they turned out to hold.
struct TimetableDiagnostics: Equatable, Sendable {
    /// Where the line-to-entry mapping came from.
    enum MappingSource: Equatable, Sendable {
        /// The copy inside the app, which ages as the archive is republished.
        case bundled
        /// A copy fetched from the project's site, saved on the device.
        case published(Date)
    }

    struct Archive: Equatable, Sendable {
        let entryCount: Int
        let publishedAt: Date?
        let downloadedAt: Date?
        let etag: String?
    }

    struct Mapping: Equatable, Sendable {
        let lineCount: Int
        let source: MappingSource
    }

    /// One entry the mapping names for a line, and whether the archive still has it.
    struct Candidate: Equatable, Sendable, Identifiable {
        let entryName: String
        let isInIndex: Bool
        let isOnDisk: Bool
        var id: String { entryName }
    }

    struct Line: Equatable, Sendable, Identifiable {
        let lineNumber: String
        let record: TimetableLineRecord?
        let candidates: [Candidate]
        let isInMemory: Bool

        var id: String { lineNumber }
        var isDownloaded: Bool { isInMemory || record?.isDownloaded == true }
        var hasFailed: Bool { record?.failure != nil }
        /// True when the timetable the app has came from a file cached for an
        /// earlier publication, rather than from the archive the index describes.
        var isFromEarlierArchive: Bool { record?.isFromEarlierArchive == true }
    }

    /// A file in the cache, told apart from the line it belongs to - which is not
    /// the same thing once the archive has been republished under new names.
    struct CacheFile: Equatable, Sendable, Identifiable {
        let name: String
        let bytes: Int
        let modifiedAt: Date?
        /// The line the file's own `Linky.txt` declares.
        let declaredLine: String?
        /// The line that would read this file today, if one would.
        let servedLine: String?
        let isInIndex: Bool

        var id: String { name }
    }

    struct Counts: Equatable, Sendable {
        let downloaded: Int
        let failed: Int
        let untouched: Int
    }

    let archive: Archive
    let mapping: Mapping
    /// Which archive the mapping was built from, when the document says.
    let mappingArchive: MappingArchive?
    /// Whether that mapping could have been built from the archive the index names.
    let freshness: MappingFreshness
    let cacheEntryCount: Int
    let cacheBytes: Int
    let cacheFiles: [CacheFile]
    let lines: [Line]
    /// The lines the app can read right now, parsed - what the browse screen lists.
    let downloaded: [DownloadedTimetable]

    var counts: Counts {
        Counts(downloaded: lines.filter { $0.isDownloaded }.count,
               failed: lines.filter { $0.hasFailed }.count,
               untouched: lines.filter { !$0.isDownloaded && !$0.hasFailed }.count)
    }

    /// The whole snapshot as text, for pasting into a bug report.
    var text: String {
        var rows: [String] = []
        rows.append("VDV Live timetable diagnostics")
        rows.append("archive: \(archive.entryCount) entries, published \(archive.publishedAt.map(Self.date) ?? "unknown"), index read \(archive.downloadedAt.map(Self.date) ?? "never"), etag \(archive.etag ?? "unknown")")
        switch mapping.source {
        case .bundled: rows.append("mapping: bundled, \(mapping.lineCount) lines")
        case .published(let date): rows.append("mapping: published, \(mapping.lineCount) lines, saved \(Self.date(date))")
        }
        rows.append("mapping archive: \(Self.describe(mappingArchive))")
        rows.append("mapping freshness: \(Self.describe(freshness))")
        rows.append("cache: \(cacheEntryCount) entry files, \(cacheBytes) bytes")
        for file in cacheFiles {
            rows.append("file \(file.name): \(file.bytes) bytes, declares \(file.declaredLine ?? "?"), serves \(file.servedLine ?? "-")\(file.isInIndex ? "" : " (not in index)")")
        }
        let counts = counts
        rows.append("lines: \(counts.downloaded) downloaded, \(counts.failed) failed, \(counts.untouched) untouched")
        for line in downloaded {
            rows.append("readable \(line.lineNumber): \(line.entryName) declares \(line.timetable.lineNumber), \(line.runs.count) runs, \(line.stopCount) stops\(line.isFromEarlierArchive ? ", from an earlier archive" : "")")
        }
        for line in lines where line.record != nil {
            let record = line.record
            let candidates = line.candidates.map { "\($0.entryName)\($0.isInIndex ? "" : " (gone)")" }.joined(separator: ", ")
            if let failure = record?.failure {
                rows.append("\(line.lineNumber): FAILED \(failure) [\(candidates)]")
            } else {
                rows.append("\(line.lineNumber): \(record?.entryName ?? "?") declares \(record?.declaredLineNumber ?? "?") [\(candidates)]")
            }
        }
        return rows.joined(separator: "\n")
    }

    private static func date(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func describe(_ archive: MappingArchive?) -> String {
        guard let archive else { return "unknown" }
        var parts: [String] = []
        if let date = archive.date { parts.append("date \(date)") }
        if let bytes = archive.bytes { parts.append("size \(bytes)") }
        if let etag = archive.etag { parts.append("etag \(etag)") }
        if let lastModified = archive.lastModified { parts.append("published \(Self.date(lastModified))") }
        return parts.isEmpty ? "unknown" : parts.joined(separator: ", ")
    }

    private static func describe(_ freshness: MappingFreshness) -> String {
        switch freshness {
        case .current: return "matches the index"
        case .unknown: return "cannot be told"
        case .stale(let mapping, let index):
            return "STALE - mapping \(Self.describe(mapping)), index \(index.etag ?? "no etag")/\(index.size) bytes"
        }
    }
}
