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
    private static let localFileSig: UInt32 = 0x04034b50
    private static let dataDescriptorSig: UInt32 = 0x08074b50

    /// Extract a ZIP archive to `destURL`. Handles STORED (0) and DEFLATE (8) compression.
    static func extract(_ zipURL: URL, to destURL: URL) throws {
        let data = try Data(contentsOf: zipURL)
        let fm = FileManager.default
        try fm.createDirectory(at: destURL, withIntermediateDirectories: true)

        var pos = 0
        while pos + 30 <= data.count {
            let sig = data.u32(pos)
            if sig != localFileSig {
                // Skip data descriptors or other blocks if they appear
                if sig == dataDescriptorSig { pos += 16 ; continue }
                // If we hit central directory signature (0x02014b50), we are done
                if sig == 0x02014b50 { break }
                pos += 1
                continue
            }

            let version        = data.u16(pos + 4)
            let flags          = data.u16(pos + 6)
            let compression    = data.u16(pos + 8)
            let compressedSize = Int(data.u32(pos + 18))
            let uncompressed   = Int(data.u32(pos + 22))
            let nameLen        = Int(data.u16(pos + 26))
            let extraLen       = Int(data.u16(pos + 28))

            let nameStart = pos + 30
            let dataStart = nameStart + nameLen + extraLen
            let dataEnd   = dataStart + compressedSize

            guard nameStart + nameLen <= data.count, dataEnd <= data.count else {
                throw ZipError.invalidFormat
            }

            let nameData = data[nameStart ..< nameStart + nameLen]
            if let name = String(data: nameData, encoding: .utf8), !name.isEmpty {
                let dest = destURL.appendingPathComponent(name)
                
                if name.hasSuffix("/") {
                    try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
                } else {
                    try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    
                    let rawData = data[dataStart ..< dataEnd]
                    if compression == 0 { // Stored
                        try rawData.write(to: dest)
                    } else if compression == 8 { // Deflate
                        let decompressed = try decompress(rawData, uncompressedSize: uncompressed)
                        try decompressed.write(to: dest)
                    } else {
                        throw ZipError.unsupportedCompression
                    }
                }
            }

            pos = dataEnd
            // Check for data descriptor flag
            if (flags & 0x08) != 0 {
                pos += 16
            }
        }
    }

    private static func decompress(_ data: Data, uncompressedSize: Int) throws -> Data {
        let bufferSize = uncompressedSize
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
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }
    func u32(_ offset: Int) -> UInt32 {
        UInt32(self[offset])        | UInt32(self[offset + 1]) << 8 |
        UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
