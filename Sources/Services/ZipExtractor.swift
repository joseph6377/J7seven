import Foundation
import Compression

enum ZipError: LocalizedError {
    case unsupportedCompression
    case invalidFormat
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedCompression:
            return "This zip uses an unsupported compression method."
        case .invalidFormat:
            return "The zip file is invalid or truncated."
        case .decompressionFailed:
            return "Failed to decompress a file within the zip."
        }
    }
}

enum ZipExtractor {
    /// Extract a ZIP archive to `destURL`. Parses the Central Directory (with ZIP64
    /// support) so streamed archives and data-descriptor entries work; a corrupt
    /// individual entry is skipped rather than failing the whole archive.
    static func extract(_ zipURL: URL, to destURL: URL) throws {
        let data = try Data(contentsOf: zipURL)
        let fm = FileManager.default
        try fm.createDirectory(at: destURL, withIntermediateDirectories: true)

        guard let eocdOffset = findEOCD(in: data) else {
            throw ZipError.invalidFormat
        }

        var totalRecords = Int(data.u16(eocdOffset + 10))
        var cdOffset = Int(data.u32(eocdOffset + 16))

        // ZIP64: sentinel values redirect to the ZIP64 end-of-central-directory record.
        if totalRecords == 0xFFFF || cdOffset == 0xFFFFFFFF {
            let locatorOffset = eocdOffset - 20
            if locatorOffset >= 0, data.u32(locatorOffset) == 0x07064b50 {
                let zip64EOCD = Int(data.u64(locatorOffset + 8))
                if zip64EOCD + 56 <= data.count, data.u32(zip64EOCD) == 0x06064b50 {
                    totalRecords = Int(data.u64(zip64EOCD + 32))
                    cdOffset = Int(data.u64(zip64EOCD + 48))
                }
            }
        }

        guard cdOffset < data.count else {
            throw ZipError.invalidFormat
        }

        var extracted = 0
        var pos = cdOffset
        entryLoop: for _ in 0..<totalRecords {
            guard pos + 46 <= data.count, data.u32(pos) == 0x02014b50 else {
                // Central directory is corrupt past this point; keep what we have.
                break entryLoop
            }

            let compression    = data.u16(pos + 10)
            var compressedSize = Int(data.u32(pos + 20))
            var uncompressed   = Int(data.u32(pos + 24))
            let nameLen        = Int(data.u16(pos + 28))
            let extraLen       = Int(data.u16(pos + 30))
            let commentLen     = Int(data.u16(pos + 32))
            var localOffset    = Int(data.u32(pos + 42))

            guard pos + 46 + nameLen + extraLen + commentLen <= data.count else {
                break entryLoop
            }
            defer { pos += 46 + nameLen + extraLen + commentLen }

            // ZIP64 extra field replaces any 32-bit sentinel values.
            if compressedSize == 0xFFFFFFFF || uncompressed == 0xFFFFFFFF || localOffset == 0xFFFFFFFF {
                let extra = data.subdata(in: pos + 46 + nameLen ..< pos + 46 + nameLen + extraLen)
                (uncompressed, compressedSize, localOffset) = zip64Values(
                    extra: extra,
                    uncompressed: uncompressed,
                    compressed: compressedSize,
                    localOffset: localOffset
                )
            }

            let nameData = data.subdata(in: pos + 46 ..< pos + 46 + nameLen)
            let name = decodeName(nameData)
            guard !name.isEmpty else { continue }

            // Zip-slip guard: validate the entry name itself rather than comparing
            // resolved filesystem paths. On iOS the destination dir exists (so its
            // path resolves the /var→/private/var symlink) while the not-yet-created
            // entry path does not, making a path-prefix check reject every entry.
            // Name-based validation is filesystem-independent and immune to that.
            let normalizedName = name.replacingOccurrences(of: "\\", with: "/")
            let comps = normalizedName.split(separator: "/", omittingEmptySubsequences: true)
            guard !normalizedName.hasPrefix("/"), !comps.contains("..") else { continue }

            let dest = destURL.appendingPathComponent(name).standardizedFileURL

            if name.hasSuffix("/") {
                try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
                extracted += 1
                continue
            }

            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

            // A single bad entry (corrupt header or stream) shouldn't abort the book.
            guard localOffset + 30 <= data.count, data.u32(localOffset) == 0x04034b50 else { continue }

            let localNameLen  = Int(data.u16(localOffset + 26))
            let localExtraLen = Int(data.u16(localOffset + 28))
            let dataStart = localOffset + 30 + localNameLen + localExtraLen
            let dataEnd   = dataStart + compressedSize
            guard dataStart <= dataEnd, dataEnd <= data.count else { continue }

            let rawData = data.subdata(in: dataStart ..< dataEnd)
            do {
                if compression == 0 { // Stored
                    try rawData.write(to: dest)
                } else if compression == 8 { // Deflate
                    let decompressed = try decompress(rawData, uncompressedSize: uncompressed)
                    try decompressed.write(to: dest)
                } else {
                    continue
                }
                extracted += 1
            } catch {
                continue
            }
        }

        guard extracted > 0 else {
            throw ZipError.invalidFormat
        }
    }

    // MARK: - ZIP64

    /// Reads 8-byte replacements from the 0x0001 extra field for any field holding
    /// the 32-bit sentinel. Values appear in spec order: uncompressed, compressed,
    /// local header offset — only for the fields that need them.
    private static func zip64Values(extra: Data, uncompressed: Int, compressed: Int,
                                    localOffset: Int) -> (Int, Int, Int) {
        var uncompressed = uncompressed, compressed = compressed, localOffset = localOffset
        var pos = 0
        while pos + 4 <= extra.count {
            let headerId = extra.u16(pos)
            let size = Int(extra.u16(pos + 2))
            if headerId == 0x0001 {
                var fieldPos = pos + 4
                let fieldEnd = min(pos + 4 + size, extra.count)
                if uncompressed == 0xFFFFFFFF, fieldPos + 8 <= fieldEnd {
                    uncompressed = Int(extra.u64(fieldPos)); fieldPos += 8
                }
                if compressed == 0xFFFFFFFF, fieldPos + 8 <= fieldEnd {
                    compressed = Int(extra.u64(fieldPos)); fieldPos += 8
                }
                if localOffset == 0xFFFFFFFF, fieldPos + 8 <= fieldEnd {
                    localOffset = Int(extra.u64(fieldPos))
                }
                break
            }
            pos += 4 + size
        }
        return (uncompressed, compressed, localOffset)
    }

    // MARK: - Filenames

    /// The zip spec says names are CP437 unless flag bit 11 marks them UTF-8, but
    /// many tools write UTF-8 without the flag — so always try UTF-8 first.
    private static func decodeName(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        return String(data.map { byte in
            byte < 0x80 ? Character(Unicode.Scalar(byte)) : cp437High[Int(byte) - 0x80]
        })
    }

    /// CP437 code points 0x80–0xFF.
    private static let cp437High: [Character] = Array(
        "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»" +
        "░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀" +
        "αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■\u{00A0}"
    )

    // MARK: - EOCD / decompression

    private static func findEOCD(in data: Data) -> Int? {
        let minPos = max(0, data.count - 65535 - 22)
        var pos = data.count - 22
        while pos >= minPos {
            if data.u32(pos) == 0x06054b50 {
                return pos
            }
            pos -= 1
        }
        return nil
    }

    private static func decompress(_ data: Data, uncompressedSize: Int) throws -> Data {
        let bufferSize = uncompressedSize
        if bufferSize == 0 { return Data() }
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }

        return try data.withUnsafeBytes { sourceBuffer in
            guard let sourceAddress = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw ZipError.decompressionFailed
            }

            let status = compression_decode_buffer(
                destinationBuffer, bufferSize,
                sourceAddress, data.count,
                nil,
                COMPRESSION_ZLIB
            )

            guard status == bufferSize else {
                throw ZipError.decompressionFailed
            }

            return Data(bytes: destinationBuffer, count: bufferSize)
        }
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }
    func u32(_ offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i])         | UInt32(self[i + 1]) << 8 |
               UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
    func u64(_ offset: Int) -> UInt64 {
        UInt64(u32(offset)) | UInt64(u32(offset + 4)) << 32
    }
}
