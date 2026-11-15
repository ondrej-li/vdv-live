import Foundation
@testable import VdvLive

/// Builds small, uncompressed zips in memory.
///
/// The archive's own fixtures are real publications, one entry each - which cannot
/// express what a line actually looks like in the archive: the same line published
/// several times, once per validity period, with different runs. Tests that need
/// that shape build it here instead of depending on what the ministry happened to
/// publish the week they were written.
///
/// Stored rather than deflated: the reader accepts both, and a stored entry needs
/// no compressor. The CRC is left at zero because `ZipArchive` does not verify it.
enum ZipFixture {
    /// A zip holding the files given, keyed by the name each should have.
    static func archive(_ files: [(name: String, contents: String)]) -> Data {
        var body = Data()
        var directory = Data()
        var count: UInt16 = 0

        for file in files {
            let name = Data(file.name.utf8)
            let payload = Data(file.contents.utf8)
            let offset = UInt32(body.count)

            body.append(localHeader(name: name, size: UInt32(payload.count)))
            body.append(payload)

            directory.append(centralDirectoryEntry(name: name,
                                                   size: UInt32(payload.count),
                                                   offset: offset))
            count += 1
        }

        var archive = body
        let directoryOffset = UInt32(body.count)
        archive.append(directory)
        archive.append(endOfCentralDirectory(entries: count,
                                             directorySize: UInt32(directory.count),
                                             directoryOffset: directoryOffset))
        return archive
    }

    /// One line's package, as an entry inside the archive holds it.
    ///
    /// - Parameters:
    ///   - lineNumber: what `Linky.txt` and the calls declare, e.g. `764337`.
    ///   - runs: the runs of the line, each with the time it departs the only stop.
    ///   - validFrom: the day the entry starts to apply, `DDMMYYYY`; the archive
    ///     publishes a line once per period and the newest started one is current.
    static func linePackage(lineNumber: String,
                            runs: [(service: String, time: String)],
                            validFrom: String = "01012026",
                            validTo: String = "12122026") -> Data {
        let linky = "\"\(lineNumber)\",\"Testovací-linka\",\"12345678\",\"V\",\"A\",\"0\",\"0\",\"0\",\"0\",\"\",\"\",\"\",\"\",\"\(validFrom)\",\"\(validTo)\",\"1\",\"1\";"
        var calls: [String] = []
        for run in runs {
            calls.append("\"\(lineNumber)\",\"\(run.service)\",\"1\",\"1\",\"\",\"\",\"\",\"\",\"0\",\"\",\"\",\"\(run.time)\",\"\",\"1\";")
        }
        let stop = "\"1\",\"Testov\",\"\",\"nám.\",\"JI\",\"CZ\",\"\",\"\",\"\",\"\",\"\",\"\";"
        let spoje = runs.map { "\"\(lineNumber)\",\"\($0.service)\",\"1\",\"14\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"1\";" }
            .joined(separator: "\n")

        return archive([
            ("Linky.txt", linky),
            ("Zasspoje.txt", calls.joined(separator: "\n")),
            ("Zastavky.txt", stop),
            ("Spoje.txt", spoje)
        ])
    }

    /// An archive holding several line packages, keyed by the names the archive
    /// gives them - which is what the mapping names.
    static func archive(entries: [(name: String, package: Data)]) -> Data {
        var body = Data()
        var directory = Data()
        var count: UInt16 = 0

        for entry in entries {
            let name = Data(entry.name.utf8)
            let offset = UInt32(body.count)
            body.append(localHeader(name: name, size: UInt32(entry.package.count)))
            body.append(entry.package)
            directory.append(centralDirectoryEntry(name: name,
                                                   size: UInt32(entry.package.count),
                                                   offset: offset))
            count += 1
        }

        var archive = body
        let directoryOffset = UInt32(body.count)
        archive.append(directory)
        archive.append(endOfCentralDirectory(entries: count,
                                             directorySize: UInt32(directory.count),
                                             directoryOffset: directoryOffset))
        return archive
    }

    // MARK: - The zip file format, only the parts a reader needs

    private static func localHeader(name: Data, size: UInt32) -> Data {
        var header = Data()
        header.append(uint32(0x0403_4b50))
        header.append(uint16(20))          // version needed
        header.append(uint16(0))           // flags
        header.append(uint16(0))           // stored
        header.append(uint16(0))           // time
        header.append(uint16(0))           // date
        header.append(uint32(0))           // crc, not verified
        header.append(uint32(size))        // compressed size
        header.append(uint32(size))        // uncompressed size
        header.append(uint16(UInt16(name.count)))
        header.append(uint16(0))           // extra length
        header.append(name)
        return header
    }

    private static func centralDirectoryEntry(name: Data, size: UInt32, offset: UInt32) -> Data {
        var entry = Data()
        entry.append(uint32(0x0201_4b50))
        entry.append(uint16(20))           // version made by
        entry.append(uint16(20))           // version needed
        entry.append(uint16(0))            // flags
        entry.append(uint16(0))            // stored
        entry.append(uint16(0))            // time
        entry.append(uint16(0))            // date
        entry.append(uint32(0))            // crc
        entry.append(uint32(size))
        entry.append(uint32(size))
        entry.append(uint16(UInt16(name.count)))
        entry.append(uint16(0))            // extra length
        entry.append(uint16(0))            // comment length
        entry.append(uint16(0))            // disk number
        entry.append(uint16(0))            // internal attributes
        entry.append(uint32(0))            // external attributes
        entry.append(uint32(offset))
        entry.append(name)
        return entry
    }

    private static func endOfCentralDirectory(entries: UInt16,
                                              directorySize: UInt32,
                                              directoryOffset: UInt32) -> Data {
        var end = Data()
        end.append(uint32(0x0605_4b50))
        end.append(uint16(0))              // this disk
        end.append(uint16(0))              // disk with the directory
        end.append(uint16(entries))
        end.append(uint16(entries))
        end.append(uint32(directorySize))
        end.append(uint32(directoryOffset))
        end.append(uint16(0))              // comment length
        return end
    }

    private static func uint16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
