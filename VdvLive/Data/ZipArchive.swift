import Compression
import Foundation

/// Reader for the two zip tricks the timetable archive needs.
///
/// The app ships without dependencies and Foundation cannot open a zip, so this
/// covers exactly what is required: read the central directory (to find an entry
/// and where its bytes live) and inflate one entry. Timetable entries are small
/// - the largest file a line needs is a few tens of kilobytes - so everything is
/// held in memory.
enum ZipArchive {
    enum Failure: Error, Equatable {
        case notAZip
        case unsupported
        case centralDirectoryNotInTail
        case entryNotFound(String)
        case damagedEntry(String)
        case couldNotInflate(String)
    }

    struct Entry: Equatable, Sendable {
        let name: String
        /// 0 is stored, 8 is deflate. Anything else is refused.
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        /// Offset of the entry's local header inside the archive.
        let localHeaderOffset: Int
    }

    // MARK: - Directory

    /// Entries of an archive held in memory.
    static func entries(in data: Data) throws -> [Entry] {
        try entries(inTail: data, archiveSize: data.count)
    }

    /// Entries described by a central directory at the very end of an archive.
    ///
    /// `tail` only has to be the end of the file - which is all a range request
    /// needs to fetch - but it has to contain the whole central directory. Entry
    /// offsets come back relative to the archive, not to `tail`.
    static func entries(inTail tail: Data, archiveSize: Int) throws -> [Entry] {
        guard archiveSize >= tail.count else { throw Failure.notAZip }
        guard let end = endOfCentralDirectory(in: tail) else { throw Failure.notAZip }
        guard end.directoryOffset != UInt32.max,
              end.directorySize != UInt32.max,
              end.entryCount != UInt16.max else {
            // The national archive is well under 4 GB with 13,259 entries, so
            // this only guards against the format changing under us.
            throw Failure.unsupported
        }
        // The watch reports a 32 bit `Int`, so an offset that does not fit is a
        // reason to give up rather than to trap.
        guard let directoryOffset = Int(exactly: end.directoryOffset),
              let directorySize = Int(exactly: end.directorySize) else {
            throw Failure.unsupported
        }

        let tailStart = archiveSize - tail.count
        let directoryStart = directoryOffset - tailStart
        guard directoryStart >= 0, directoryStart + directorySize <= tail.count else {
            throw Failure.centralDirectoryNotInTail
        }

        var entries: [Entry] = []
        entries.reserveCapacity(end.entryCount)
        var cursor = directoryStart
        for _ in 0..<end.entryCount {
            guard cursor + 46 <= tail.count, uint32(tail, cursor) == 0x0201_4B50 else {
                throw Failure.notAZip
            }
            let nameLength = uint16(tail, cursor + 28)
            let extraLength = uint16(tail, cursor + 30)
            let commentLength = uint16(tail, cursor + 32)
            let nameStart = cursor + 46
            guard nameStart + nameLength <= tail.count else { throw Failure.notAZip }

            let name = String(
                data: tail.subdata(in: nameStart..<(nameStart + nameLength)),
                encoding: .utf8
            ) ?? ""
            entries.append(
                Entry(
                    name: name,
                    method: UInt16(uint16(tail, cursor + 10)),
                    compressedSize: Int(uint32(tail, cursor + 20)),
                    uncompressedSize: Int(uint32(tail, cursor + 24)),
                    localHeaderOffset: Int(uint32(tail, cursor + 42))
                )
            )
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    // MARK: - Contents

    /// Contents of `entry`, read out of the archive it belongs to.
    static func contents(of entry: Entry, in archive: Data) throws -> Data {
        guard entry.localHeaderOffset >= 0, entry.localHeaderOffset < archive.count else {
            throw Failure.damagedEntry(entry.name)
        }
        return try contents(of: entry, from: archive, startingAt: entry.localHeaderOffset)
    }

    /// Contents of `entry`, given bytes that *start* at its local header.
    ///
    /// This is exactly what a range request for the entry returns, and it is why
    /// the two calls are kept apart: handing this one a whole archive would read
    /// whichever entry happens to come first.
    static func contents(of entry: Entry, fromLocalHeader bytes: Data) throws -> Data {
        try contents(of: entry, from: bytes, startingAt: 0)
    }

    private static func contents(of entry: Entry, from bytes: Data, startingAt offset: Int) throws -> Data {
        guard bytes.count - offset >= 30, uint32(bytes, offset) == 0x0403_4B50 else {
            throw Failure.damagedEntry(entry.name)
        }
        let nameLength = uint16(bytes, offset + 26)
        let extraLength = uint16(bytes, offset + 28)
        let dataStart = offset + 30 + nameLength + extraLength
        let dataEnd = dataStart + entry.compressedSize
        guard dataEnd <= bytes.count else { throw Failure.damagedEntry(entry.name) }

        let payload = bytes.subdata(in: dataStart..<dataEnd)
        return try inflate(
            payload,
            method: entry.method,
            uncompressedSize: entry.uncompressedSize,
            name: entry.name
        )
    }

    /// The entry's stored or deflated bytes as they were before compression.
    static func inflate(
        _ payload: Data,
        method: UInt16,
        uncompressedSize: Int,
        name: String
    ) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }

        switch method {
        case 0:
            return payload
        case 8:
            let inflated = inflateRawDeflate(payload, uncompressedSize: uncompressedSize)
            guard inflated.count == uncompressedSize else { throw Failure.couldNotInflate(name) }
            return inflated
        default:
            throw Failure.damagedEntry(name)
        }
    }

    // MARK: - Internals

    /// Raw deflate, which is what zip stores. `COMPRESSION_ZLIB` in Apple's
    /// framework is the deflate algorithm itself, without the two byte zlib
    /// header, so it reads zip entries directly.
    private static func inflateRawDeflate(_ payload: Data, uncompressedSize: Int) -> Data {
        var output = Data(count: uncompressedSize)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            payload.withUnsafeBytes { source -> Int in
                guard let destinationAddress = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceAddress = source.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    destinationAddress,
                    uncompressedSize,
                    sourceAddress,
                    payload.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        return written == uncompressedSize ? output : output.prefix(written)
    }

    private struct EndOfCentralDirectory {
        let entryCount: Int
        let directorySize: UInt32
        let directoryOffset: UInt32
    }

    /// Scans backwards for the end of central directory record, which is the
    /// only way to find the directory: it can sit up to 64 KB before the end.
    private static func endOfCentralDirectory(in data: Data) -> EndOfCentralDirectory? {
        let signature: UInt32 = 0x0605_4B50
        let minimumSize = 22
        guard data.count >= minimumSize else { return nil }

        let lastPossible = data.count - minimumSize
        let firstPossible = max(0, lastPossible - 0xFFFF)
        var cursor = lastPossible
        while cursor >= firstPossible {
            if uint32(data, cursor) == signature {
                return EndOfCentralDirectory(
                    entryCount: uint16(data, cursor + 10),
                    directorySize: uint32(data, cursor + 12),
                    directoryOffset: uint32(data, cursor + 16)
                )
            }
            cursor -= 1
        }
        return nil
    }

    private static func uint16(_ data: Data, _ offset: Int) -> Int {
        let start = data.startIndex + offset
        return Int(data[start]) | Int(data[start + 1]) << 8
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return UInt32(data[start])
            | UInt32(data[start + 1]) << 8
            | UInt32(data[start + 2]) << 16
            | UInt32(data[start + 3]) << 24
    }
}
