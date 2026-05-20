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
    /// Extract a ZIP archive to `destURL`. Parses the Central Directory to support
    /// streamed archives and files utilizing general purpose bit flag 3 (data descriptors).
    static func extract(_ zipURL: URL, to destURL: URL) throws {
        let data = try Data(contentsOf: zipURL)
        let fm = FileManager.default
        try fm.createDirectory(at: destURL, withIntermediateDirectories: true)

        guard let eocdOffset = findEOCD(in: data) else {
            throw ZipError.invalidFormat
        }
        
        let totalRecords = Int(data.u16(eocdOffset + 10))
        let cdOffset = Int(data.u32(eocdOffset + 16))

        guard cdOffset < data.count else {
            throw ZipError.invalidFormat
        }

        var pos = cdOffset
        for _ in 0..<totalRecords {
            guard pos + 46 <= data.count else {
                throw ZipError.invalidFormat
            }
            
            let sig = data.u32(pos)
            guard sig == 0x02014b50 else {
                throw ZipError.invalidFormat
            }
            
            let compression    = data.u16(pos + 10)
            let compressedSize = Int(data.u32(pos + 20))
            let uncompressed   = Int(data.u32(pos + 24))
            let nameLen        = Int(data.u16(pos + 28))
            let extraLen       = Int(data.u16(pos + 30))
            let commentLen     = Int(data.u16(pos + 32))
            let localOffset    = Int(data.u32(pos + 42))
            
            guard pos + 46 + nameLen + extraLen + commentLen <= data.count else {
                throw ZipError.invalidFormat
            }
            
            let nameData = data[pos + 46 ..< pos + 46 + nameLen]
            if let name = String(data: nameData, encoding: .utf8), !name.isEmpty {
                let dest = destURL.appendingPathComponent(name)
                
                if name.hasSuffix("/") {
                    try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
                } else {
                    try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    
                    guard localOffset + 30 <= data.count else {
                        throw ZipError.invalidFormat
                    }
                    let localSig = data.u32(localOffset)
                    guard localSig == 0x04034b50 else {
                        throw ZipError.invalidFormat
                    }
                    
                    let localNameLen  = Int(data.u16(localOffset + 26))
                    let localExtraLen = Int(data.u16(localOffset + 28))
                    
                    let dataStart = localOffset + 30 + localNameLen + localExtraLen
                    let dataEnd   = dataStart + compressedSize
                    
                    guard dataEnd <= data.count else {
                        throw ZipError.invalidFormat
                    }
                    
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
            
            pos += 46 + nameLen + extraLen + commentLen
        }
    }

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
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }
    func u32(_ offset: Int) -> UInt32 {
        UInt32(self[offset])        | UInt32(self[offset + 1]) << 8 |
        UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
