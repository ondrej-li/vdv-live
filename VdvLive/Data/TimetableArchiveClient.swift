import Foundation

/// The official timetable archive and how to read pieces of it.
enum TimetableArchive {
    /// JDF export of the Ministry of Transport, three times a week.
    static let address = URL(string: "https://portal.cisjr.cz/pub/JDF/JDF.zip")!

    /// The central directory of 13,259 entries runs to well under this, and a
    /// range request for the end of the file is enough to read it.
    static let directoryTailBytes = 2 * 1_024 * 1_024

    /// One byte is not read for its contents: the response's headers say which
    /// publication of the archive the server is offering.
    static let versionProbeBytes = 1
}

/// Which publication of the archive the server is offering.
///
/// The portal rebuilds the archive three times a week, so an index that was read
/// a week ago is out of date and nothing inside it says so. The response to a
/// small range request carries the three things that identify the file, which is
/// what makes "is my copy current?" a question worth a kilobyte.
struct ArchiveVersion: Codable, Equatable, Sendable {
    /// The file's identity, and the first thing to compare.
    var etag: String?
    /// When the portal published it.
    var lastModified: Date?
    /// Size in bytes, the weakest of the three: a rebuild can leave it the same
    /// size, so it is only used when the server offers nothing better.
    var size: Int

    /// Whether two responses describe the same publication.
    func describesSamePublication(as other: ArchiveVersion) -> Bool {
        if let mine = etag, let theirs = other.etag { return mine == theirs }
        if let mine = lastModified, let theirs = other.lastModified { return mine == theirs }
        return size == other.size
    }
}

enum TimetableError: Error, Equatable, LocalizedError {
    /// The index has not been downloaded yet.
    case notDownloaded
    /// The server answered with the whole archive instead of the range asked for.
    case rangeNotSupported
    case unrecognisedResponse
    /// A line the app knows about is not in the archive any more.
    case lineNotInArchive(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notDownloaded:
            return String(localized: "Timetables have not been downloaded yet.")
        case .rangeNotSupported:
            return String(localized: "The timetable server refused a partial download.")
        case .unrecognisedResponse:
            return String(localized: "The timetable server sent an unexpected response.")
        case .lineNotInArchive(let line):
            return String(
                format: String(localized: "Line %@ is not in the published timetable."),
                line
            )
        case .transport(let message):
            return message
        }
    }
}

/// Reads the archive: the central directory, and single entries out of it.
protocol TimetableArchiveReading: Sendable {
    /// Every entry of the archive, taken from its central directory.
    func entries() async throws -> [ZipArchive.Entry]
    /// The contents of one entry - for a line, that is the zip holding its
    /// timetable files.
    func contents(of entry: ZipArchive.Entry) async throws -> Data
    /// Which publication of the archive the server is offering now, without
    /// reading any of it.
    func version() async throws -> ArchiveVersion
}

/// The live archive, read with range requests.
///
/// A line's whole timetable is a few kilobytes, so the app never downloads the
/// 106 MB archive: it reads the directory once, then only the entries it needs.
struct HTTPTimetableArchive: TimetableArchiveReading {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func entries() async throws -> [ZipArchive.Entry] {
        let tail = try await directoryTail(bytes: TimetableArchive.directoryTailBytes)
        do {
            return try ZipArchive.entries(inTail: tail.data, archiveSize: tail.size)
        } catch ZipArchive.Failure.centralDirectoryNotInTail {
            // The guess was too small, which should not happen; ask for more
            // rather than give up.
            let bigger = try await directoryTail(bytes: TimetableArchive.directoryTailBytes * 4)
            return try ZipArchive.entries(inTail: bigger.data, archiveSize: bigger.size)
        }
    }

    func contents(of entry: ZipArchive.Entry) async throws -> Data {
        // The local header's own name and extra lengths are only known after
        // reading it, so a little slack is requested; the parser reads exactly
        // what the header says it needs.
        let slack = 512
        let last = entry.localHeaderOffset + entry.compressedSize + slack
        let data = try await range(from: entry.localHeaderOffset, to: last)
        do {
            return try ZipArchive.contents(of: entry, fromLocalHeader: data)
        } catch ZipArchive.Failure.damagedEntry {
            // Header longer than the slack, which has never been seen: fetch the
            // entry again with room to spare.
            let roomier = try await range(from: entry.localHeaderOffset, to: last + 4_096)
            return try ZipArchive.contents(of: entry, fromLocalHeader: roomier)
        }
    }

    // MARK: - Ranges

    /// What the server is offering, read out of the headers of a one byte range
    /// request. Nothing else of the archive is fetched.
    func version() async throws -> ArchiveVersion {
        var request = URLRequest(url: TimetableArchive.address)
        request.setValue(
            "bytes=0-\(TimetableArchive.versionProbeBytes - 1)",
            forHTTPHeaderField: "Range"
        )
        request.setValue("VdvLive", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, response) = try await send(request)
        guard let size = totalSize(from: response, isPartial: true) else {
            throw response.statusCode == 200 ? TimetableError.rangeNotSupported
                : TimetableError.unrecognisedResponse
        }
        return ArchiveVersion(
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified")
                .flatMap(Self.httpDate),
            size: size
        )
    }

    /// `Wed, 30 Sep 2026 19:49:29 GMT`, the only date format the portal uses.
    private static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }

    private func directoryTail(bytes: Int) async throws -> (data: Data, size: Int) {
        var request = URLRequest(url: TimetableArchive.address)
        request.setValue("bytes=-\(bytes)", forHTTPHeaderField: "Range")
        request.setValue("VdvLive", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await send(request)
        guard let size = totalSize(from: response, isPartial: true) else {
            // A server that ignores Range would hand over the whole 106 MB.
            throw response.statusCode == 200 ? TimetableError.rangeNotSupported
                : TimetableError.unrecognisedResponse
        }
        return (data, size)
    }

    private func range(from start: Int, to end: Int) async throws -> Data {
        var request = URLRequest(url: TimetableArchive.address)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        request.setValue("VdvLive", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await send(request)
        guard totalSize(from: response, isPartial: false) != nil else {
            throw response.statusCode == 200 ? TimetableError.rangeNotSupported
                : TimetableError.unrecognisedResponse
        }
        return data
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw TimetableError.unrecognisedResponse
            }
            return (data, http)
        } catch let error as TimetableError {
            throw error
        } catch {
            throw TimetableError.transport(
                (error as? URLError)?.localizedDescription ?? error.localizedDescription
            )
        }
    }

    /// Size of the whole archive, read out of `Content-Range: bytes 0-99/106842823`.
    private func totalSize(from response: HTTPURLResponse, isPartial: Bool) -> Int? {
        if let header = response.value(forHTTPHeaderField: "Content-Range"),
           let size = header.split(separator: "/").last.flatMap({ Int($0) }) {
            return size
        }
        // Without a Content-Range the answer is the whole file, which is only
        // acceptable when the whole file was asked for.
        guard !isPartial, response.statusCode == 206 else { return nil }
        return Int(response.expectedContentLength)
    }
}
