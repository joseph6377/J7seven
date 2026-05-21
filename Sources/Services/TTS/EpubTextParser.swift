import Foundation

/// A chapter extracted from a text-only EPUB (no media overlay required).
struct EpubChapter {
    let title: String
    let paragraphs: [String]   // plain text, one per <p>, empty strings removed
}

enum EpubTextParserError: LocalizedError {
    case missingContainer
    case missingOPF
    case invalidOPF
    case noTextContent

    var errorDescription: String? {
        switch self {
        case .missingContainer: return "Not a valid EPUB: missing META-INF/container.xml"
        case .missingOPF:       return "Missing package document (OPF file)"
        case .invalidOPF:       return "The OPF file is malformed"
        case .noTextContent:    return "No readable text content found in this EPUB"
        }
    }
}

enum EpubTextParser {

    struct ParsedBook {
        let title: String
        let author: String
        let slug: String
        let coverData: Data?
        let chapters: [EpubChapter]
    }

    static func parse(epubURL: URL) throws -> ParsedBook {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }

        // 1. Unzip EPUB
        try ZipExtractor.extract(epubURL, to: tempDir)

        // 2. container.xml → OPF path
        let containerURL = tempDir.appendingPathComponent("META-INF/container.xml")
        guard let containerData = try? Data(contentsOf: containerURL) else {
            throw EpubTextParserError.missingContainer
        }
        let container = XMLIndexer(data: containerData)
        guard let opfPath = container.child("container")?
                .child("rootfiles")?
                .child("rootfile")?
                .attributes["full-path"] else {
            throw EpubTextParserError.missingOPF
        }

        let opfURL     = tempDir.appendingPathComponent(opfPath)
        let opfDir     = opfURL.deletingLastPathComponent()
        let opfRelDir  = (opfPath as NSString).deletingLastPathComponent

        guard let opfData = try? Data(contentsOf: opfURL),
              let opf = XMLIndexer(data: opfData).child("package") else {
            throw EpubTextParserError.missingOPF
        }

        // 3. Metadata
        let metadata = opf.child("metadata")
        let title    = metadata?.child("title")?.text   ?? "Unknown Title"
        let author   = metadata?.child("creator")?.text ?? "Unknown Author"
        let slug     = epubURL.deletingPathExtension().lastPathComponent
                           .lowercased()
                           .replacingOccurrences(of: " ", with: "-")

        // 4. Manifest item map
        var itemsById: [String: (href: String, type: String, properties: String?)] = [:]
        if let manifest = opf.child("manifest") {
            for item in manifest.children(named: "item") {
                guard let id   = item.attributes["id"],
                      let href = item.attributes["href"],
                      let type = item.attributes["media-type"] else { continue }
                itemsById[id] = (href, type, item.attributes["properties"])
            }
        }

        // 5. Cover image
        var coverData: Data? = nil
        if let coverId = metadata?.children(named: "meta")
                .first(where: { $0.attributes["name"] == "cover" })?.attributes["content"],
           let coverHref = itemsById[coverId]?.href {
            coverData = try? Data(contentsOf: opfDir.appendingPathComponent(coverHref))
        } else if let coverItem = itemsById.values.first(where: {
            $0.type.hasPrefix("image/") && $0.href.lowercased().contains("cover")
        }) {
            coverData = try? Data(contentsOf: opfDir.appendingPathComponent(coverItem.href))
        }

        // 6. TOC titles (nav doc first, NCX fallback)
        var tocTitles: [String: String] = [:]
        if let navItem = itemsById.values.first(where: {
            ($0.properties ?? "").contains("nav")
        }) {
            let navURL    = opfDir.appendingPathComponent(navItem.href)
            let navRelDir = (normalize(base: opfRelDir, path: navItem.href) as NSString).deletingLastPathComponent
            if let navData = try? Data(contentsOf: navURL) {
                let navRoot = XMLIndexer(data: navData)
                let tocNav  = navRoot.allDescendants.first {
                    $0.name == "nav" || $0.name.hasSuffix(":nav")
                }
                for anchor in tocNav?.allDescendants ?? [] where anchor.name == "a" || anchor.name.hasSuffix(":a") {
                    guard let rawHref = anchor.attributes["href"], !rawHref.isEmpty else { continue }
                    let cleanHref = rawHref.components(separatedBy: "#").first ?? rawHref
                    let key       = normalize(base: navRelDir, path: cleanHref)
                    let label     = collectText(anchor)
                    if !label.isEmpty { tocTitles[key] = label }
                }
            }
        }

        // NCX fallback for EPUB 2.0 and other books missing an HTML nav document
        if tocTitles.isEmpty, let ncxItem = itemsById.values.first(where: {
            $0.type == "application/x-dtbncx+xml" || $0.href.hasSuffix(".ncx")
        }) {
            let ncxURL    = opfDir.appendingPathComponent(ncxItem.href)
            let ncxRelDir = (normalize(base: opfRelDir, path: ncxItem.href) as NSString).deletingLastPathComponent
            if let ncxData = try? Data(contentsOf: ncxURL) {
                let ncxRoot = XMLIndexer(data: ncxData)
                let navPoints = ncxRoot.allDescendants.filter {
                    let local = $0.name.components(separatedBy: ":").last ?? $0.name
                    return local == "navPoint"
                }
                for navPoint in navPoints {
                    guard let contentNode = navPoint.child("content"),
                          let rawSrc = contentNode.attributes["src"], !rawSrc.isEmpty else { continue }
                    
                    let cleanSrc = rawSrc.components(separatedBy: "#").first ?? rawSrc
                    let key      = normalize(base: ncxRelDir, path: cleanSrc)
                    
                    if let textNode = navPoint.child("navLabel")?.child("text") {
                        let label = textNode.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !label.isEmpty {
                            tocTitles[key] = label
                        }
                    }
                }
            }
        }

        // 7. Spine → chapters of plain text
        var chapters: [EpubChapter] = []
        if let spine = opf.child("spine") {
            for itemref in spine.children(named: "itemref") {
                guard let idref   = itemref.attributes["idref"],
                      let item    = itemsById[idref],
                      item.type.contains("xhtml") else { continue }

                let htmlURL = opfDir.appendingPathComponent(item.href)
                guard let htmlData = try? Data(contentsOf: htmlURL) else { continue }

                let paragraphs = extractParagraphs(from: htmlData)
                guard !paragraphs.isEmpty else { continue }

                let key    = normalize(base: opfRelDir, path: item.href)
                let chTitle = tocTitles[key] ?? "Chapter \(chapters.count + 1)"
                chapters.append(EpubChapter(title: chTitle, paragraphs: paragraphs))
            }
        }

        guard !chapters.isEmpty else { throw EpubTextParserError.noTextContent }
        return ParsedBook(title: title, author: author, slug: slug, coverData: coverData, chapters: chapters)
    }

    // MARK: - Plain text extraction

    /// Returns plain text for every non-empty <p> element in an XHTML document.
    private static func extractParagraphs(from data: Data) -> [String] {
        let root = XMLIndexer(data: data)
        let allP = root.allDescendants.filter { $0.name == "p" || $0.name.hasSuffix(":p") }
        return allP
            .map { collectText($0) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Helpers (mirrors EpubParser internals)

    private static func normalize(base: String, path: String) -> String {
        if base.isEmpty { return (path as NSString).standardizingPath }
        return ("\(base)/\(path)" as NSString).standardizingPath
    }

    private static func collectText(_ node: XMLIndexer) -> String {
        var parts: [String] = []
        if !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(node.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        for child in node.children { parts.append(collectText(child)) }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
