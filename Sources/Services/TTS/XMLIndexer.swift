import Foundation

/// Lightweight XML/XHTML tree built on Foundation's XMLParser.
/// Covers the DOM-navigation subset used by EpubTextParser.
final class XMLIndexer {
    /// A text run or a child element, retained in document order so callers that
    /// care about reading order (e.g. inline drop-cap spans) can reconstruct it.
    enum Content {
        case text(String)
        case element(XMLIndexer)
    }

    let name: String
    var text: String = ""
    let attributes: [String: String]
    var children: [XMLIndexer] = []
    /// Text runs and child elements interleaved in document order. `text` and
    /// `children` are kept alongside for navigation; this preserves ordering.
    var orderedContent: [Content] = []

    /// False when XMLParser aborted before the end of the document — the tree may be
    /// partial/truncated and callers should fall back to a lenient HTML parser.
    private(set) var parseSucceeded: Bool = true

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
        parseSucceeded = parser.parse()
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

    // MARK: - Decoding & sanitization

    /// Decode raw bytes to text: BOM sniff, then the XML declaration's encoding
    /// attribute, then UTF-8, then 8-bit fallbacks that accept any byte sequence.
    static func decodeText(_ data: Data) -> String {
        if data.count >= 3, data[data.startIndex] == 0xEF,
           data[data.startIndex + 1] == 0xBB, data[data.startIndex + 2] == 0xBF {
            if let s = String(data: data.dropFirst(3), encoding: .utf8) { return s }
        }
        if data.count >= 2 {
            let b0 = data[data.startIndex], b1 = data[data.startIndex + 1]
            if (b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF) {
                if let s = String(data: data, encoding: .utf16) { return s }
            }
        }
        if let declared = declaredEncoding(in: data),
           let s = String(data: data, encoding: declared) {
            return s
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Reads `encoding="..."` from an XML declaration in the first bytes of the document.
    private static func declaredEncoding(in data: Data) -> String.Encoding? {
        let head = data.prefix(200).map { $0 < 0x80 ? Character(Unicode.Scalar($0)) : "?" }
        let headText = String(head)
        guard let range = headText.range(of: #"encoding=["']([^"']+)["']"#,
                                         options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let match = headText[range]
        guard let q1 = match.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        let name = match[match.index(after: q1)...].dropLast().lowercased()
        switch name {
        case "utf-8", "utf8", "us-ascii", "ascii": return .utf8
        case "utf-16", "utf-16le", "utf-16be":     return .utf16
        case "iso-8859-1", "latin1", "latin-1":    return .isoLatin1
        case "windows-1252", "cp-1252", "cp1252":  return .windowsCP1252
        default: return nil
        }
    }

    /// Decode bytes and rewrite the markup so the strict XMLParser can cope:
    /// resolve HTML named entities, escape stray ampersands, and strip the
    /// DOCTYPE plus any stale encoding declaration.
    private static func sanitize(_ data: Data) -> Data {
        var text = decodeText(data)
        guard !text.isEmpty else { return data }

        // We hand XMLParser UTF-8 bytes, so a stale declared encoding would mislead it.
        text = text.replacingOccurrences(
            of: #"(<\?xml[^>]*?)\s+encoding=["'][^"']*["']"#,
            with: "$1", options: .regularExpression)
        // External DTD references make XMLParser reject the named entities we resolve below.
        text = text.replacingOccurrences(
            of: #"<!DOCTYPE[^>\[]*(\[[^\]]*\])?[^>]*>"#,
            with: "", options: [.regularExpression, .caseInsensitive])

        text = resolveNamedEntities(in: text)
        text = escapeStrayAmpersands(in: text)
        return Data(text.utf8)
    }

    /// Replace HTML named entities with their characters; unknown names are escaped
    /// to literal text so XMLParser never sees an undefined entity.
    private static func resolveNamedEntities(in text: String) -> String {
        guard text.contains("&") else { return text }
        guard let regex = try? NSRegularExpression(pattern: "&([a-zA-Z][a-zA-Z0-9]{1,31});") else {
            return text
        }
        let ns = text as NSString
        var out = ""
        out.reserveCapacity(ns.length)
        var last = 0
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let entityName = ns.substring(with: match.range(at: 1))
            if xmlPredefined.contains(entityName) {
                out += ns.substring(with: match.range)
            } else if let scalarValue = htmlEntities[entityName],
                      let scalar = Unicode.Scalar(scalarValue) {
                out.append(Character(scalar))
            } else {
                out += "&amp;\(entityName);"
            }
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Escape `&` characters that don't start a valid entity reference.
    private static func escapeStrayAmpersands(in text: String) -> String {
        guard text.contains("&") else { return text }
        return text.replacingOccurrences(
            of: #"&(?!(?:[a-zA-Z][a-zA-Z0-9]{0,31}|#[0-9]{1,7}|#x[0-9a-fA-F]{1,6});)"#,
            with: "&amp;", options: .regularExpression)
    }

    private static let xmlPredefined: Set<String> = ["amp", "lt", "gt", "quot", "apos"]

    /// Full HTML4 named character reference table (entity name → Unicode scalar value).
    private static let htmlEntities: [String: UInt32] = [
        // Latin-1 (160–255)
        "nbsp": 160, "iexcl": 161, "cent": 162, "pound": 163, "curren": 164, "yen": 165,
        "brvbar": 166, "sect": 167, "uml": 168, "copy": 169, "ordf": 170, "laquo": 171,
        "not": 172, "shy": 173, "reg": 174, "macr": 175, "deg": 176, "plusmn": 177,
        "sup2": 178, "sup3": 179, "acute": 180, "micro": 181, "para": 182, "middot": 183,
        "cedil": 184, "sup1": 185, "ordm": 186, "raquo": 187, "frac14": 188, "frac12": 189,
        "frac34": 190, "iquest": 191, "Agrave": 192, "Aacute": 193, "Acirc": 194,
        "Atilde": 195, "Auml": 196, "Aring": 197, "AElig": 198, "Ccedil": 199,
        "Egrave": 200, "Eacute": 201, "Ecirc": 202, "Euml": 203, "Igrave": 204,
        "Iacute": 205, "Icirc": 206, "Iuml": 207, "ETH": 208, "Ntilde": 209,
        "Ograve": 210, "Oacute": 211, "Ocirc": 212, "Otilde": 213, "Ouml": 214,
        "times": 215, "Oslash": 216, "Ugrave": 217, "Uacute": 218, "Ucirc": 219,
        "Uuml": 220, "Yacute": 221, "THORN": 222, "szlig": 223, "agrave": 224,
        "aacute": 225, "acirc": 226, "atilde": 227, "auml": 228, "aring": 229,
        "aelig": 230, "ccedil": 231, "egrave": 232, "eacute": 233, "ecirc": 234,
        "euml": 235, "igrave": 236, "iacute": 237, "icirc": 238, "iuml": 239,
        "eth": 240, "ntilde": 241, "ograve": 242, "oacute": 243, "ocirc": 244,
        "otilde": 245, "ouml": 246, "divide": 247, "oslash": 248, "ugrave": 249,
        "uacute": 250, "ucirc": 251, "uuml": 252, "yacute": 253, "thorn": 254, "yuml": 255,
        // Latin Extended / punctuation / special
        "OElig": 338, "oelig": 339, "Scaron": 352, "scaron": 353, "Yuml": 376,
        "fnof": 402, "circ": 710, "tilde": 732,
        "ensp": 8194, "emsp": 8195, "thinsp": 8201, "zwnj": 8204, "zwj": 8205,
        "lrm": 8206, "rlm": 8207, "ndash": 8211, "mdash": 8212, "lsquo": 8216,
        "rsquo": 8217, "sbquo": 8218, "ldquo": 8220, "rdquo": 8221, "bdquo": 8222,
        "dagger": 8224, "Dagger": 8225, "bull": 8226, "hellip": 8230, "permil": 8240,
        "prime": 8242, "Prime": 8243, "lsaquo": 8249, "rsaquo": 8250, "oline": 8254,
        "frasl": 8260, "euro": 8364,
        // Greek
        "Alpha": 913, "Beta": 914, "Gamma": 915, "Delta": 916, "Epsilon": 917,
        "Zeta": 918, "Eta": 919, "Theta": 920, "Iota": 921, "Kappa": 922,
        "Lambda": 923, "Mu": 924, "Nu": 925, "Xi": 926, "Omicron": 927, "Pi": 928,
        "Rho": 929, "Sigma": 931, "Tau": 932, "Upsilon": 933, "Phi": 934, "Chi": 935,
        "Psi": 936, "Omega": 937, "alpha": 945, "beta": 946, "gamma": 947,
        "delta": 948, "epsilon": 949, "zeta": 950, "eta": 951, "theta": 952,
        "iota": 953, "kappa": 954, "lambda": 955, "mu": 956, "nu": 957, "xi": 958,
        "omicron": 959, "pi": 960, "rho": 961, "sigmaf": 962, "sigma": 963,
        "tau": 964, "upsilon": 965, "phi": 966, "chi": 967, "psi": 968, "omega": 969,
        "thetasym": 977, "upsih": 978, "piv": 982,
        // Math / symbols / arrows
        "weierp": 8472, "image": 8465, "real": 8476, "trade": 8482, "alefsym": 8501,
        "larr": 8592, "uarr": 8593, "rarr": 8594, "darr": 8595, "harr": 8596,
        "crarr": 8629, "lArr": 8656, "uArr": 8657, "rArr": 8658, "dArr": 8659,
        "hArr": 8660, "forall": 8704, "part": 8706, "exist": 8707, "empty": 8709,
        "nabla": 8711, "isin": 8712, "notin": 8713, "ni": 8715, "prod": 8719,
        "sum": 8721, "minus": 8722, "lowast": 8727, "radic": 8730, "prop": 8733,
        "infin": 8734, "ang": 8736, "and": 8743, "or": 8744, "cap": 8745, "cup": 8746,
        "int": 8747, "there4": 8756, "sim": 8764, "cong": 8773, "asymp": 8776,
        "ne": 8800, "equiv": 8801, "le": 8804, "ge": 8805, "sub": 8834, "sup": 8835,
        "nsub": 8836, "sube": 8838, "supe": 8839, "oplus": 8853, "otimes": 8855,
        "perp": 8869, "sdot": 8901, "lceil": 8968, "rceil": 8969, "lfloor": 8970,
        "rfloor": 8971, "lang": 9001, "rang": 9002, "loz": 9674, "spades": 9824,
        "clubs": 9827, "hearts": 9829, "diams": 9830,
    ]
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
        stack.last?.orderedContent.append(.element(node))
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
        stack.last?.orderedContent.append(.text(string))
    }

    func parser(_ parser: XMLParser, foundCDATA cdataBlock: Data) {
        if let s = String(data: cdataBlock, encoding: .utf8) {
            stack.last?.text += s
            stack.last?.orderedContent.append(.text(s))
        }
    }
}
