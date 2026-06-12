import Foundation

/// A chapter extracted from a text-only EPUB (no media overlay required).
struct EpubChapter {
    let title: String
    let paragraphs: [Paragraph]   // plain text, one per block element, empty strings removed
}

enum EpubTextParserError: LocalizedError {
    case missingContainer
    case missingOPF
    case invalidOPF
    case noTextContent
    case drmProtected

    var errorDescription: String? {
        switch self {
        case .missingContainer: return "Not a valid EPUB: missing META-INF/container.xml"
        case .missingOPF:       return "Missing package document (OPF file)"
        case .invalidOPF:       return "The OPF file is malformed"
        case .noTextContent:    return "No readable text content found in this EPUB"
        case .drmProtected:     return "This EPUB is DRM-protected (e.g. Adobe or LCP) and can't be imported."
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

        // 2. DRM check — encrypted content can't be parsed, so fail with a clear message
        if isDRMProtected(root: tempDir) {
            throw EpubTextParserError.drmProtected
        }

        // 3. Locate and load the OPF package document
        let (opfURL, opfPath) = try locateOPF(root: tempDir)
        let opfDir    = opfURL.deletingLastPathComponent()
        let opfRelDir = (opfPath as NSString).deletingLastPathComponent

        guard let opfData = try? Data(contentsOf: opfURL),
              let opf = XMLIndexer(data: opfData).child("package") else {
            throw EpubTextParserError.missingOPF
        }

        // 4. Metadata
        let metadata = opf.child("metadata")
        let title    = metadata?.child("title")?.text.trimmingCharacters(in: .whitespacesAndNewlines)
                           .nonEmpty ?? "Unknown Title"
        let author   = metadata?.child("creator")?.text.trimmingCharacters(in: .whitespacesAndNewlines)
                           .nonEmpty ?? "Unknown Author"
        let slug     = epubURL.deletingPathExtension().lastPathComponent
                           .lowercased()
                           .replacingOccurrences(of: " ", with: "-")

        // 5. Manifest item map
        var itemsById: [String: (href: String, type: String, properties: String?)] = [:]
        if let manifest = opf.child("manifest") {
            for item in manifest.children(named: "item") {
                guard let id   = item.attributes["id"],
                      let href = item.attributes["href"] else { continue }
                itemsById[id] = (href, item.attributes["media-type"] ?? "", item.attributes["properties"])
            }
        }

        // 6. Cover image: EPUB3 cover-image property, then EPUB2 <meta name="cover">,
        //    then any image whose path mentions "cover"
        var coverData: Data? = nil
        if let coverItem = itemsById.values.first(where: {
            ($0.properties ?? "").components(separatedBy: " ").contains("cover-image")
        }), let url = resolveFile(href: coverItem.href, relativeTo: opfDir, root: tempDir) {
            coverData = try? Data(contentsOf: url)
        }
        if coverData == nil,
           let coverId = metadata?.children(named: "meta")
                .first(where: { $0.attributes["name"] == "cover" })?.attributes["content"],
           let coverHref = itemsById[coverId]?.href,
           let url = resolveFile(href: coverHref, relativeTo: opfDir, root: tempDir) {
            coverData = try? Data(contentsOf: url)
        }
        if coverData == nil, let coverItem = itemsById.values.first(where: {
            $0.type.hasPrefix("image/") && $0.href.lowercased().contains("cover")
        }), let url = resolveFile(href: coverItem.href, relativeTo: opfDir, root: tempDir) {
            coverData = try? Data(contentsOf: url)
        }

        // 7. TOC titles (nav doc first, NCX fallback)
        var tocTitles: [String: String] = [:]
        if let navItem = itemsById.values.first(where: {
            ($0.properties ?? "").contains("nav")
        }) {
            let navRelDir = (normalize(base: opfRelDir, path: navItem.href) as NSString).deletingLastPathComponent
            if let navURL = resolveFile(href: navItem.href, relativeTo: opfDir, root: tempDir),
               let navData = try? Data(contentsOf: navURL) {
                let navRoot = XMLIndexer(data: navData)
                let tocNav  = navRoot.allDescendants.first {
                    $0.name == "nav" || $0.name.hasSuffix(":nav")
                }
                for anchor in tocNav?.allDescendants ?? [] where anchor.name == "a" || anchor.name.hasSuffix(":a") {
                    guard let rawHref = anchor.attributes["href"], !rawHref.isEmpty else { continue }
                    let key   = normalize(base: navRelDir, path: rawHref)
                    let label = ChapterTextExtractor.collectText(anchor)
                    if !label.isEmpty { tocTitles[key] = label }
                }
            }
        }

        // NCX fallback for EPUB 2.0 and other books missing an HTML nav document
        if tocTitles.isEmpty, let ncxItem = itemsById.values.first(where: {
            $0.type == "application/x-dtbncx+xml" || $0.href.hasSuffix(".ncx")
        }) {
            let ncxRelDir = (normalize(base: opfRelDir, path: ncxItem.href) as NSString).deletingLastPathComponent
            if let ncxURL = resolveFile(href: ncxItem.href, relativeTo: opfDir, root: tempDir),
               let ncxData = try? Data(contentsOf: ncxURL) {
                let ncxRoot = XMLIndexer(data: ncxData)
                let navPoints = ncxRoot.allDescendants.filter {
                    let local = $0.name.components(separatedBy: ":").last ?? $0.name
                    return local == "navPoint"
                }
                for navPoint in navPoints {
                    guard let contentNode = navPoint.child("content"),
                          let rawSrc = contentNode.attributes["src"], !rawSrc.isEmpty else { continue }

                    let key = normalize(base: ncxRelDir, path: rawSrc)

                    if let textNode = navPoint.child("navLabel")?.child("text") {
                        let label = textNode.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !label.isEmpty {
                            tocTitles[key] = label
                        }
                    }
                }
            }
        }

        // 8. Spine → chapters of plain text
        var chapters: [EpubChapter] = []
        if let spine = opf.child("spine") {
            for itemref in spine.children(named: "itemref") {
                // linear="no" items are kept: excluding them drops real content
                // (prefaces, notes) far more often than it filters junk.
                guard let idref = itemref.attributes["idref"],
                      let item  = itemsById[idref],
                      isContentDocument(href: item.href, type: item.type) else { continue }

                guard let htmlURL = resolveFile(href: item.href, relativeTo: opfDir, root: tempDir),
                      let htmlData = try? Data(contentsOf: htmlURL) else { continue }

                let paragraphs = ChapterTextExtractor.extract(from: htmlData)
                guard !paragraphs.isEmpty else { continue }

                let key     = normalize(base: opfRelDir, path: item.href)
                let chTitle = tocTitles[key] ?? "Chapter \(chapters.count + 1)"
                chapters.append(EpubChapter(title: chTitle, paragraphs: paragraphs))
            }
        }

        guard !chapters.isEmpty else {
            // Books with an Adobe rights file but unencrypted-looking structure
            // still fail here — surface DRM rather than a generic error.
            if FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("META-INF/rights.xml").path) {
                throw EpubTextParserError.drmProtected
            }
            throw EpubTextParserError.noTextContent
        }
        return ParsedBook(title: title, author: author, slug: slug, coverData: coverData, chapters: chapters)
    }

    // MARK: - OPF discovery

    /// Find the package document: container.xml (case-insensitive) → its rootfile,
    /// or, when no container exists, the shallowest .opf file in the archive.
    private static func locateOPF(root: URL) throws -> (url: URL, relPath: String) {
        let fm = FileManager.default

        if let containerURL = findCaseInsensitive(path: "META-INF/container.xml", under: root),
           let containerData = try? Data(contentsOf: containerURL) {
            let container = XMLIndexer(data: containerData)
            let rootfiles = container.child("container")?.child("rootfiles")?
                .children(named: "rootfile") ?? []
            let chosen = rootfiles.first {
                $0.attributes["media-type"] == "application/oebps-package+xml"
            } ?? rootfiles.first
            guard var fullPath = chosen?.attributes["full-path"], !fullPath.isEmpty else {
                throw EpubTextParserError.missingOPF
            }
            fullPath = fullPath.removingPercentEncoding ?? fullPath
            if fullPath.hasPrefix("/") { fullPath = String(fullPath.dropFirst()) }
            guard let url = resolveFile(href: fullPath, relativeTo: root, root: root) else {
                throw EpubTextParserError.missingOPF
            }
            return (url, fullPath)
        }

        // No container.xml: some malformed EPUBs still carry a valid package document.
        let opfCandidates = (fm.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "opf" }) ?? []
        if let opfURL = opfCandidates.min(by: { $0.pathComponents.count < $1.pathComponents.count }) {
            let relPath = opfURL.path.replacingOccurrences(of: root.path + "/", with: "")
            return (opfURL, relPath)
        }
        throw EpubTextParserError.missingContainer
    }

    /// Looks up a relative path, falling back to case-insensitive matching per component.
    private static func findCaseInsensitive(path: String, under root: URL) -> URL? {
        let fm = FileManager.default
        let exact = root.appendingPathComponent(path)
        if fm.fileExists(atPath: exact.path) { return exact }

        var current = root
        for component in path.components(separatedBy: "/") where !component.isEmpty {
            guard let contents = try? fm.contentsOfDirectory(atPath: current.path),
                  let match = contents.first(where: { $0.lowercased() == component.lowercased() }) else {
                return nil
            }
            current = current.appendingPathComponent(match)
        }
        return fm.fileExists(atPath: current.path) ? current : nil
    }

    // MARK: - DRM detection

    /// True when META-INF/encryption.xml encrypts content documents (font obfuscation
    /// is fine), or an LCP license is present.
    private static func isDRMProtected(root: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("META-INF/license.lcpl").path) {
            return true
        }
        let encryptionURL = root.appendingPathComponent("META-INF/encryption.xml")
        guard let data = try? Data(contentsOf: encryptionURL) else { return false }

        let fontObfuscationAlgorithms: Set<String> = [
            "http://www.idpf.org/2008/embedding",
            "http://ns.adobe.com/pdf/enc#RC",
        ]
        let contentExtensions: Set<String> = ["xhtml", "html", "htm", "opf", "ncx"]

        let rootNode = XMLIndexer(data: data)
        for encryptedData in rootNode.allDescendants where localName(encryptedData.name) == "EncryptedData" {
            let algorithm = encryptedData.allDescendants
                .first { localName($0.name) == "EncryptionMethod" }?
                .attributes["Algorithm"] ?? ""
            let uri = encryptedData.allDescendants
                .first { localName($0.name) == "CipherReference" }?
                .attributes["URI"] ?? ""
            let ext = (uri.components(separatedBy: "#").first ?? uri)
                .components(separatedBy: ".").last?.lowercased() ?? ""
            if contentExtensions.contains(ext) { return true }
            if !fontObfuscationAlgorithms.contains(algorithm), !algorithm.isEmpty,
               !ext.isEmpty, !["ttf", "otf", "woff", "woff2"].contains(ext) {
                return true
            }
        }
        return false
    }

    private static func localName(_ n: String) -> String {
        n.components(separatedBy: ":").last ?? n
    }

    // MARK: - Spine filtering

    /// Accept anything that plausibly holds chapter markup — media-types lie often
    /// enough that the file extension is also consulted.
    private static func isContentDocument(href: String, type: String) -> Bool {
        let lowerType = type.lowercased()
        if lowerType.contains("dtbncx") { return false }
        if lowerType.contains("xhtml") || lowerType.contains("html") { return true }
        let path = (href.components(separatedBy: "#").first ?? href)
            .components(separatedBy: "?").first ?? href
        let ext = (path as NSString).pathExtension.lowercased()
        return ["xhtml", "html", "htm"].contains(ext)
    }

    // MARK: - Path resolution

    /// Resolve a manifest/nav href to an extracted file: strips fragments and queries,
    /// decodes percent-encoding, supports absolute (archive-rooted) paths, and falls
    /// back to a case-insensitive match on the final path component.
    private static func resolveFile(href: String, relativeTo dir: URL, root: URL) -> URL? {
        var path = href.components(separatedBy: "#").first ?? href
        path = path.components(separatedBy: "?").first ?? path
        path = path.removingPercentEncoding ?? path
        guard !path.isEmpty else { return nil }

        let base: URL
        if path.hasPrefix("/") {
            base = root
            path = String(path.dropFirst())
        } else {
            base = dir
        }
        let url = base.appendingPathComponent(path).standardizedFileURL
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return url }

        let parent = url.deletingLastPathComponent()
        let lastLower = url.lastPathComponent.lowercased()
        if let contents = try? fm.contentsOfDirectory(atPath: parent.path),
           let match = contents.first(where: { $0.lowercased() == lastLower }) {
            return parent.appendingPathComponent(match)
        }
        return nil
    }

    /// Normalized archive-relative key used to match spine items against TOC hrefs.
    private static func normalize(base: String, path: String) -> String {
        var p = path.components(separatedBy: "#").first ?? path
        p = p.components(separatedBy: "?").first ?? p
        p = p.removingPercentEncoding ?? p
        if p.hasPrefix("/") { return (String(p.dropFirst()) as NSString).standardizingPath }
        if base.isEmpty { return (p as NSString).standardizingPath }
        return ("\(base)/\(p)" as NSString).standardizingPath
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
