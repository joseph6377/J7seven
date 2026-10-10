import Foundation
import SwiftSoup

/// Extracts plain-text paragraphs from a chapter's (X)HTML.
///
/// Two passes: a strict XMLParser-based pass for well-formed XHTML (the common,
/// fast case), and a lenient SwiftSoup pass for malformed markup that the strict
/// parser truncates or rejects. Both passes collect text per block-level element,
/// so books that use <div>/<li>/headings instead of <p> still produce paragraphs.
/// Headings are only used when a document has no other block content, so chapter
/// titles aren't read aloud in normally structured books.
enum ChapterTextExtractor {

    static func extract(from data: Data) -> [Paragraph] {
        let root = XMLIndexer(data: data)
        let strict = extractStrict(root)
        if root.parseSucceeded && !strict.isEmpty {
            return strict.map { Paragraph(text: $0, pageNumber: nil) }
        }
        // Strict parse aborted (possibly truncating the chapter) or found nothing:
        // reparse leniently and keep whichever pass recovered more text.
        let lenient = extractLenient(XMLIndexer.decodeText(data))
        let chosen = lenient.joined().count >= strict.joined().count ? lenient : strict
        return chosen.map { Paragraph(text: $0, pageNumber: nil) }
    }

    // MARK: - Strict pass (XMLIndexer)

    private static let primaryTags: Set<String> = [
        "p", "li", "blockquote", "dd", "dt", "td", "th", "pre", "figcaption",
    ]
    private static let headingTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]
    /// Containers treated as paragraphs only when nothing block-level is nested inside.
    private static let containerTags: Set<String> = ["div", "section"]

    private static func extractStrict(_ root: XMLIndexer) -> [String] {
        var out: [String] = []
        walk(root, into: &out, includeHeadings: false)
        if out.isEmpty {
            walk(root, into: &out, includeHeadings: true)
        }
        return out
    }

    private static func walk(_ node: XMLIndexer, into out: inout [String], includeHeadings: Bool) {
        if isArtifact(node) { return }
        let local = localName(node.name)
        let isBlock = primaryTags.contains(local) || containerTags.contains(local)
            || (includeHeadings && headingTags.contains(local))
        if isBlock, !containsBlock(node, includeHeadings: includeHeadings) {
            let text = collectText(node)
            if !text.isEmpty { out.append(text) }
            return
        }
        for child in node.children { walk(child, into: &out, includeHeadings: includeHeadings) }
    }

    private static func containsBlock(_ node: XMLIndexer, includeHeadings: Bool) -> Bool {
        node.children.contains { child in
            guard !isArtifact(child) else { return false }
            let local = localName(child.name)
            return primaryTags.contains(local) || containerTags.contains(local)
                || (includeHeadings && headingTags.contains(local))
                || containsBlock(child, includeHeadings: includeHeadings)
        }
    }

    private static func localName(_ n: String) -> String {
        n.components(separatedBy: ":").last ?? n
    }

    // MARK: - Structural artifact exclusion (footnotes, pagebreaks, noterefs)

    /// `epub:type`/`role` tokens that always mark a note/pagebreak container,
    /// regardless of its text content.
    private static let alwaysExciseTypes: Set<String> = [
        "pagebreak", "footnote", "footnotes", "endnote", "endnotes", "noteref",
    ]
    private static let alwaysExciseRoles: Set<String> = [
        "doc-pagebreak", "doc-footnote", "doc-endnote", "doc-endnotes", "doc-noteref",
    ]
    /// Bibliography/glossary references often wrap ordinary prose words, so these
    /// are only excised when their own text is a bare marker (e.g. "12", "a").
    private static let markerOnlyTypes: Set<String> = ["biblioref", "glossref"]

    private static let markerPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^[\[\(]?[0-9]{1,4}[\]\)]?$|^[a-zA-Z]$|^[*†‡§¶]+$"#)
    }()

    private static func isMarkerText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return markerPattern.firstMatch(in: trimmed, range: range) != nil
    }

    /// Reads an attribute by local name, tolerating a namespace prefix XMLParser
    /// left unresolved on the key (e.g. `epub:type` when asked for `type`).
    private static func attributeLocal(_ node: XMLIndexer, _ localKey: String) -> String? {
        if let v = node.attributes[localKey] { return v }
        for (k, v) in node.attributes where localName(k) == localKey {
            return v
        }
        return nil
    }

    /// True for footnote/endnote/pagebreak containers and noterefs (always excised),
    /// bibliography/glossary refs whose text is a bare marker, and legacy anchor-based
    /// footnote refs (`<a href="#...">1</a>`) with no ARIA/epub:type markup at all.
    private static func isArtifact(_ node: XMLIndexer) -> Bool {
        let epubType = attributeLocal(node, "type")?.lowercased()
        let role = node.attributes["role"]?.lowercased()
        let typeTokens = Set((epubType ?? "").components(separatedBy: .whitespaces))
        let roleTokens = Set((role ?? "").components(separatedBy: .whitespaces))

        if !typeTokens.isDisjoint(with: alwaysExciseTypes) { return true }
        if !roleTokens.isDisjoint(with: alwaysExciseRoles) { return true }
        if !typeTokens.isDisjoint(with: markerOnlyTypes) {
            return isMarkerText(collectText(node))
        }
        if epubType == nil, role == nil, localName(node.name) == "a",
           (node.attributes["href"] ?? "").hasPrefix("#") {
            return isMarkerText(collectText(node))
        }
        return false
    }

    static func collectText(_ node: XMLIndexer) -> String {
        // Concatenate text in document order with no inserted separators: inline
        // children (drop-cap spans, <em>, <a>…) must join seamlessly with the
        // surrounding text ("<span>I</span>n 1862" → "In 1862"), relying on the
        // source's own whitespace. Then collapse whitespace runs to single spaces.
        let raw = rawInOrder(node)
        return raw.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func rawInOrder(_ node: XMLIndexer) -> String {
        var out = ""
        for item in node.orderedContent {
            switch item {
            case .text(let t):
                out += t
            case .element(let child):
                guard !isArtifact(child) else { continue }
                out += rawInOrder(child)
            }
        }
        return out
    }

    // MARK: - Lenient pass (SwiftSoup)

    private static let primarySelector =
        "p, li, blockquote, dd, dt, td, th, pre, figcaption, div, section"
    private static let headingSelector = primarySelector + ", h1, h2, h3, h4, h5, h6"

    private static func extractLenient(_ html: String) -> [String] {
        guard !html.isEmpty, let doc = try? SwiftSoup.parse(html) else { return [] }
        removeArtifacts(doc)
        var out = selectLeafBlocks(doc, selector: primarySelector)
        if out.isEmpty {
            out = selectLeafBlocks(doc, selector: headingSelector)
        }
        if out.isEmpty, let bodyText = try? doc.body()?.text() {
            let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        return out
    }

    /// Detaches footnote/endnote/pagebreak/noteref elements (and marker-only
    /// biblio/glossary refs, and legacy anchor-based footnote refs) before block
    /// selection, mirroring `isArtifact` in the strict pass.
    private static func removeArtifacts(_ doc: Document) {
        guard let all = try? doc.select("*").array() else { return }
        for el in all where isArtifactLenient(el) {
            try? el.remove()
        }
    }

    private static func isArtifactLenient(_ el: Element) -> Bool {
        let epubType = ((try? el.attr("epub:type")) ?? "").lowercased()
        let role = ((try? el.attr("role")) ?? "").lowercased()
        let typeTokens = Set(epubType.components(separatedBy: .whitespaces))
        let roleTokens = Set(role.components(separatedBy: .whitespaces))

        if !typeTokens.isDisjoint(with: alwaysExciseTypes) { return true }
        if !roleTokens.isDisjoint(with: alwaysExciseRoles) { return true }
        if !typeTokens.isDisjoint(with: markerOnlyTypes) {
            let text = (try? el.text()) ?? ""
            return isMarkerText(text)
        }
        if epubType.isEmpty, role.isEmpty, el.tagName() == "a",
           ((try? el.attr("href")) ?? "").hasPrefix("#") {
            let text = (try? el.text()) ?? ""
            return isMarkerText(text)
        }
        return false
    }

    private static func selectLeafBlocks(_ doc: Document, selector: String) -> [String] {
        guard let elements = try? doc.select(selector) else { return [] }
        var out: [String] = []
        for element in elements.array() {
            // An element whose subtree contains another block element would
            // duplicate its descendants' text — only emit leaf blocks.
            guard let inner = try? element.select(selector), inner.size() == 1,
                  let text = try? element.text() else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        return out
    }
}
