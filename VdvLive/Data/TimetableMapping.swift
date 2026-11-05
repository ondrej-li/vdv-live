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

/// The document both the bundle and the site carry.
struct TimetableMappingDocument: Decodable, Sendable {
    let lines: [String: [String]]

    /// Reads a mapping only if it is shaped like one and names enough lines to be
    /// the region's timetable rather than half a download or an error page.
    static func decode(_ data: Data, minimumLines: Int = 100) -> [String: [String]]? {
        guard let document = try? JSONDecoder().decode(TimetableMappingDocument.self, from: data),
              document.lines.count >= minimumLines,
              document.lines.values.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        return document.lines
    }
}
