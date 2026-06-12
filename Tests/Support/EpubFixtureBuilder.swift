import Foundation

/// Builds EPUB (zip) fixtures in memory for tests. Writes stored-only (compression 0)
/// archives, optionally with ZIP64 structures, and supports raw filename bytes for
/// non-UTF8 (CP437) entry-name tests.
struct EpubFixtureBuilder {

    struct Entry {
        let nameBytes: Data
        let content: Data
        let utf8Flag: Bool
    }

    private(set) var entries: [Entry] = []

    mutating func addFile(_ name: String, _ content: String) {
        addFile(name, data: Data(content.utf8))
    }

    mutating func addFile(_ name: String, data: Data) {
        entries.append(Entry(nameBytes: Data(name.utf8), content: data, utf8Flag: true))
    }

    mutating func addRawEntry(nameBytes: Data, content: Data, utf8Flag: Bool) {
        entries.append(Entry(nameBytes: nameBytes, content: content, utf8Flag: utf8Flag))
    }

    func write(to url: URL, forceZip64: Bool = false) throws {
        try zipData(forceZip64: forceZip64).write(to: url)
    }

    func zipData(forceZip64: Bool = false) -> Data {
        var out = Data()
        var localOffsets: [Int] = []

        for entry in entries {
            localOffsets.append(out.count)
            let crc = Self.crc32(entry.content)
            out.appendU32(0x04034b50)
            out.appendU16(forceZip64 ? 45 : 20)            // version needed
            out.appendU16(entry.utf8Flag ? 0x0800 : 0)     // general purpose flags
            out.appendU16(0)                               // compression: stored
            out.appendU16(0); out.appendU16(0)             // mod time/date
            out.appendU32(crc)
            out.appendU32(UInt32(entry.content.count))     // compressed
            out.appendU32(UInt32(entry.content.count))     // uncompressed
            out.appendU16(UInt16(entry.nameBytes.count))
            out.appendU16(0)                               // extra len
            out.append(entry.nameBytes)
            out.append(entry.content)
        }

        let cdOffset = out.count
        for (i, entry) in entries.enumerated() {
            let crc = Self.crc32(entry.content)
            var extra = Data()
            if forceZip64 {
                extra.appendU16(0x0001)
                extra.appendU16(24)
                extra.appendU64(UInt64(entry.content.count))   // uncompressed
                extra.appendU64(UInt64(entry.content.count))   // compressed
                extra.appendU64(UInt64(localOffsets[i]))       // local header offset
            }
            out.appendU32(0x02014b50)
            out.appendU16(forceZip64 ? 45 : 20)            // version made by
            out.appendU16(forceZip64 ? 45 : 20)            // version needed
            out.appendU16(entry.utf8Flag ? 0x0800 : 0)
            out.appendU16(0)                               // compression: stored
            out.appendU16(0); out.appendU16(0)             // mod time/date
            out.appendU32(crc)
            out.appendU32(forceZip64 ? 0xFFFFFFFF : UInt32(entry.content.count))
            out.appendU32(forceZip64 ? 0xFFFFFFFF : UInt32(entry.content.count))
            out.appendU16(UInt16(entry.nameBytes.count))
            out.appendU16(UInt16(extra.count))
            out.appendU16(0)                               // comment len
            out.appendU16(0)                               // disk start
            out.appendU16(0)                               // internal attrs
            out.appendU32(0)                               // external attrs
            out.appendU32(forceZip64 ? 0xFFFFFFFF : UInt32(localOffsets[i]))
            out.append(entry.nameBytes)
            out.append(extra)
        }
        let cdSize = out.count - cdOffset

        if forceZip64 {
            let zip64EOCDOffset = out.count
            out.appendU32(0x06064b50)
            out.appendU64(44)                              // size of remaining record
            out.appendU16(45); out.appendU16(45)           // version made by / needed
            out.appendU32(0); out.appendU32(0)             // disk numbers
            out.appendU64(UInt64(entries.count))           // entries on this disk
            out.appendU64(UInt64(entries.count))           // total entries
            out.appendU64(UInt64(cdSize))
            out.appendU64(UInt64(cdOffset))

            out.appendU32(0x07064b50)                      // zip64 EOCD locator
            out.appendU32(0)
            out.appendU64(UInt64(zip64EOCDOffset))
            out.appendU32(1)
        }

        out.appendU32(0x06054b50)
        out.appendU16(0); out.appendU16(0)                 // disk numbers
        out.appendU16(forceZip64 ? 0xFFFF : UInt16(entries.count))
        out.appendU16(forceZip64 ? 0xFFFF : UInt16(entries.count))
        out.appendU32(forceZip64 ? 0xFFFFFFFF : UInt32(cdSize))
        out.appendU32(forceZip64 ? 0xFFFFFFFF : UInt32(cdOffset))
        out.appendU16(0)                                   // comment len
        return out
    }

    // MARK: - Standard book

    /// container.xml + OPF + chapters in one call; every part overridable.
    static func standardBook(
        opfPath: String = "OEBPS/content.opf",
        containerXML: String? = nil,
        containerPath: String = "META-INF/container.xml",
        title: String = "Test Book",
        author: String = "Test Author",
        manifestItems: [(id: String, href: String, mediaType: String, properties: String?)],
        spine: [(idref: String, linear: Bool)],
        chapterFiles: [String: String],
        extraFiles: [String: String] = [:]
    ) -> EpubFixtureBuilder {
        var builder = EpubFixtureBuilder()
        builder.addFile("mimetype", "application/epub+zip")

        let container = containerXML ?? """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="\(opfPath)" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        builder.addFile(containerPath, container)

        let manifestXML = manifestItems.map { item in
            let props = item.properties.map { " properties=\"\($0)\"" } ?? ""
            return "<item id=\"\(item.id)\" href=\"\(item.href)\" media-type=\"\(item.mediaType)\"\(props)/>"
        }.joined(separator: "\n    ")
        let spineXML = spine.map { ref in
            let linear = ref.linear ? "" : " linear=\"no\""
            return "<itemref idref=\"\(ref.idref)\"\(linear)/>"
        }.joined(separator: "\n    ")

        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(title)</dc:title>
            <dc:creator>\(author)</dc:creator>
            <dc:language>en</dc:language>
          </metadata>
          <manifest>
            \(manifestXML)
          </manifest>
          <spine>
            \(spineXML)
          </spine>
        </package>
        """
        builder.addFile(opfPath, opf)

        let opfDir = (opfPath as NSString).deletingLastPathComponent
        for (href, body) in chapterFiles {
            let path = opfDir.isEmpty ? href : "\(opfDir)/\(href)"
            builder.addFile(path, body)
        }
        for (path, content) in extraFiles {
            builder.addFile(path, content)
        }
        return builder
    }

    /// Wraps body markup in a minimal XHTML document.
    static func xhtml(body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>t</title></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendU16(_ v: UInt16) {
        append(UInt8(v & 0xFF)); append(UInt8(v >> 8))
    }
    mutating func appendU32(_ v: UInt32) {
        append(UInt8(v & 0xFF)); append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF)); append(UInt8((v >> 24) & 0xFF))
    }
    mutating func appendU64(_ v: UInt64) {
        appendU32(UInt32(v & 0xFFFFFFFF)); appendU32(UInt32(v >> 32))
    }
}
