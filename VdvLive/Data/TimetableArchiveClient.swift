import Foundation

/// The official timetable archive and how to read pieces of it.
enum TimetableArchive {
    /// JDF export of the Ministry of Transport, three times a week.
    static let address = URL(string: "https://portal.cisjr.cz/pub/JDF/JDF.zip")!

    /// The central directory of 13,259 entries runs to well under this, and a
    /// range request for the end of the file is enough to read it.
    static let directoryTailBytes = 2 * 1_024 * 1_024
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
