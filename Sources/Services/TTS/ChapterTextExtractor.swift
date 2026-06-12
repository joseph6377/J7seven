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
            let local = localName(child.name)
            return primaryTags.contains(local) || containerTags.contains(local)
                || (includeHeadings && headingTags.contains(local))
                || containsBlock(child, includeHeadings: includeHeadings)
        }
    }

    private static func localName(_ n: String) -> String {
        n.components(separatedBy: ":").last ?? n
    }

    static func collectText(_ node: XMLIndexer) -> String {
        var parts: [String] = []
        let trimmed = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let collapsed = trimmed.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            parts.append(collapsed)
        }
        for child in node.children { parts.append(collectText(child)) }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Lenient pass (SwiftSoup)

    private static let primarySelector =
        "p, li, blockquote, dd, dt, td, th, pre, figcaption, div, section"
    private static let headingSelector = primarySelector + ", h1, h2, h3, h4, h5, h6"

    private static func extractLenient(_ html: String) -> [String] {
        guard !html.isEmpty, let doc = try? SwiftSoup.parse(html) else { return [] }
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
