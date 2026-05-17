import Foundation

/// Lightweight XML/XHTML tree built on Foundation's XMLParser.
/// Covers the DOM-navigation subset used by EpubTextParser.
final class XMLIndexer {
    let name: String
    var text: String = ""
    let attributes: [String: String]
    var children: [XMLIndexer] = []

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    /// Parse XML/XHTML data. Always returns a valid (possibly empty) root node.
    init(data: Data) {
        name = "#document"
        attributes = [:]
        let sanitized = XMLIndexer.sanitize(data)
        let handler = ParseHandler(root: self)
        let parser = XMLParser(data: sanitized)
        parser.shouldProcessNamespaces = true
        parser.delegate = handler
        parser.parse()
    }

    // MARK: - Navigation

    func child(_ name: String) -> XMLIndexer? {
        let q = localName(name)
        return children.first { localName($0.name) == q }
    }

    func children(named name: String) -> [XMLIndexer] {
        let q = localName(name)
        return children.filter { localName($0.name) == q }
    }

    var allDescendants: [XMLIndexer] {
        var out: [XMLIndexer] = []
        for c in children {
            out.append(c)
            out.append(contentsOf: c.allDescendants)
        }
        return out
    }

    // MARK: - Helpers

    private func localName(_ n: String) -> String {
        n.components(separatedBy: ":").last ?? n
    }

    /// Replace HTML entities that XML doesn't define so XMLParser doesn't choke.
    private static func sanitize(_ data: Data) -> Data {
        guard var text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1) else { return data }
        let entities: [(String, String)] = [
            ("&nbsp;",   "\u{00A0}"), ("&mdash;",  "\u{2014}"), ("&ndash;",  "\u{2013}"),
            ("&ldquo;",  "\u{201C}"), ("&rdquo;",  "\u{201D}"), ("&lsquo;",  "\u{2018}"),
            ("&rsquo;",  "\u{2019}"), ("&hellip;", "\u{2026}"), ("&copy;",   "\u{00A9}"),
            ("&reg;",    "\u{00AE}"), ("&trade;",  "\u{2122}"), ("&euro;",   "\u{20AC}"),
            ("&laquo;",  "\u{00AB}"), ("&raquo;",  "\u{00BB}"), ("&bull;",   "\u{2022}"),
            ("&middot;", "\u{00B7}"), ("&shy;",    "\u{00AD}"), ("&thinsp;", "\u{2009}"),
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text.data(using: .utf8) ?? data
    }
}

// MARK: - SAX handler

private final class ParseHandler: NSObject, XMLParserDelegate {
    private var stack: [XMLIndexer]

    init(root: XMLIndexer) { stack = [root] }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI _: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let node = XMLIndexer(name: qName ?? elementName, attributes: attributeDict)
        stack.last?.children.append(node)
        stack.append(node)
    }

    func parser(_ parser: XMLParser,
                didEndElement _: String,
                namespaceURI _: String?,
                qualifiedName _: String?) {
        if stack.count > 1 { stack.removeLast() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, foundCDATA cdataBlock: Data) {
        if let s = String(data: cdataBlock, encoding: .utf8) { stack.last?.text += s }
    }
}
