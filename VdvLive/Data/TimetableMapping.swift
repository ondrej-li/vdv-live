import Foundation

/// Where a fresher line-to-entry mapping than the bundled one comes from.
///
/// The archive is rebuilt three times a week and renumbers every entry, so the
/// mapping shipped in the app is only true for the publication it was built from.
/// Without a way to refresh it, a build stops resolving any line the moment the
/// ministry publishes again - which is exactly what "line not in the published
/// timetable" means, on every line, all at once.
protocol TimetableMappingFetching: Sendable {
    func latestMapping() async throws -> Data
}

/// Reads the mapping the project publishes with its own site.
///
/// A static file, no query, no identifiers: it is the same bytes every visitor
/// would get, and the app sends nothing along with the request.
struct HTTPTimetableMapping: TimetableMappingFetching {
    /// Where `make site-deploy` publishes the mapping.
    static let address = URL(string: "https://vdv.ondralinek.cz/jdf-lines.json")!

    var session: URLSession = .shared

    func latestMapping() async throws -> Data {
        var request = URLRequest(url: Self.address,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("VdvLive/1.0 (+https://github.com/ondrej-li/vdv-live)",
                         forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TimetableError.transport("The mapping response was not HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TimetableError.transport("The mapping server answered \(http.statusCode).")
        }
        guard !data.isEmpty else {
            throw TimetableError.transport("The mapping was empty.")
        }
        return data
    }
}

/// The published mapping kept on the device, so a refresh survives a relaunch.
struct TimetableMappingFiles: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? SharedContainer.timetableDirectory
    }

    private var url: URL { directory.appendingPathComponent("jdf-lines.json") }

    func load() -> Data? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data
    }

    func modifiedAt() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    func save(_ data: Data) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Which publication of the archive a mapping was built from.
///
/// A mapping is only true for the archive it was read out of: the ministry
/// renumbers every entry when it republishes, so a mapping that names one
/// publication's entries answers "not in the published timetable" for every line
/// once the next one arrives. Keeping the identity of the archive with the mapping
/// is what lets the app notice that before it tells a reader their line is gone.
struct MappingArchive: Codable, Equatable, Sendable {
    /// The JDF version date, `DDMMYYYY`, as the archive's own `VerzeJDF.txt` writes it.
    var date: String?
    /// Identity of the file the mapping was built from, when the builder had it.
    var etag: String?
    /// When the portal published that file.
    var lastModified: Date?
    /// Size of the archive in bytes, which every publication change alters.
    var bytes: Int?

    var isEmpty: Bool {
        date == nil && etag == nil && lastModified == nil && bytes == nil
    }

    private enum CodingKeys: String, CodingKey {
        case date, etag, lastModified, bytes
    }

    /// Written by tools/publish-mapping.py as an ISO 8601 string, which is what the
    /// portal's `Last-Modified` header already is; older documents carry nothing.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try? values.decodeIfPresent(String.self, forKey: .date)
        etag = try? values.decodeIfPresent(String.self, forKey: .etag)
        bytes = try? values.decodeIfPresent(Int.self, forKey: .bytes)
        if let text = try? values.decodeIfPresent(String.self, forKey: .lastModified) {
            lastModified = ISO8601DateFormatter().date(from: text)
        } else {
            lastModified = nil
        }
    }

    init(date: String? = nil,
         etag: String? = nil,
         lastModified: Date? = nil,
         bytes: Int? = nil) {
        self.date = date
        self.etag = etag
        self.lastModified = lastModified
        self.bytes = bytes
    }
}

/// Whether the mapping in force could have been built from the archive the index
/// was read from.
///
/// Compared by whichever identity both sides carry, strongest first: an ETag is
/// the file's own identity, the publication date and the size the next best.
/// Nothing comparable means nothing can be said - which is what a mapping written
/// before the identity was recorded, or an index read from a server that would not
/// say, leaves behind.
enum MappingFreshness: Equatable, Sendable {
    /// The mapping names entries of the archive the index was read from.
    case current
    /// The archive has been republished since, so every entry the mapping names
    /// holds another line now.
    case stale(mapping: MappingArchive, index: ArchiveVersion)
    /// Neither side says enough to tell.
    case unknown

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    /// What the two identities say about each other, by the strongest pair both
    /// carry: the ETag is the file's own identity, its size the next most reliable,
    /// and the publication date the last.
    static func between(mapping: MappingArchive, index: ArchiveVersion) -> MappingFreshness {
        func verdict(_ same: Bool) -> MappingFreshness {
            same ? .current : .stale(mapping: mapping, index: index)
        }

        if let mine = mapping.etag, let theirs = index.etag {
            return verdict(mine == theirs)
        }
        if let mine = mapping.bytes {
            return verdict(mine == index.size)
        }
        if let mine = mapping.lastModified, let theirs = index.lastModified {
            return verdict(mine == theirs)
        }
        return .unknown
    }
}

/// The document both the bundle and the site carry.
struct TimetableMappingDocument: Decodable, Sendable {
    let lines: [String: [String]]
    /// Which archive the mapping was built from, missing in documents written
    /// before the builder recorded it.
    let archive: MappingArchive?

    /// Reads a mapping only if it is shaped like one and names enough lines to be
    /// the region's timetable rather than half a download or an error page.
    static func decode(_ data: Data, minimumLines: Int = 100) -> [String: [String]]? {
        read(data, minimumLines: minimumLines)?.lines
    }

    /// The whole document, identity included, when it is one.
    static func read(_ data: Data, minimumLines: Int = 100) -> TimetableMappingDocument? {
        guard let document = try? JSONDecoder().decode(TimetableMappingDocument.self, from: data),
              document.lines.count >= minimumLines,
              document.lines.values.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        return document
    }
}
