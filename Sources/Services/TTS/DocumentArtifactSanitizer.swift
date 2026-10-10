import Foundation
import NaturalLanguage

/// Deterministic cleanup of citation markers, figure/table references, soft
/// hyphens, and embedded URLs left over in EPUB/PDF paragraph text, so TTS
/// doesn't read out "bracket one bracket" or "open paren see figure four
/// close paren". Distinct from `TtsTextNormalizer` (web-flavored transforms
/// like currency/date/initialism expansion that don't belong on novels).
enum DocumentArtifactSanitizer {

    static func sanitize(paragraphs: [Paragraph], language: String) -> [Paragraph] {
        paragraphs.compactMap { paragraph in
            let cleaned = sanitize(text: paragraph.text, language: language)
            guard !cleaned.isEmpty else { return nil }
            return Paragraph(text: cleaned, pageNumber: paragraph.pageNumber)
        }
    }

    static func sanitize(text: String, language: String) -> String {
        var result = text

        result = removeSoftHyphens(result)
        result = removeBracketedCitations(result)
        // Author-year citations and Fig./Tab. abbreviations are English-specific
        // conventions; applying them to other languages risks mangling prose
        // that happens to contain a parenthetical year.
        if language == "en" {
            result = removeAuthorYearCitations(result)
            result = normalizeFigureTableReferences(result)
        }
        result = TtsTextNormalizer.normalizeURLs(result)
        result = collapseWhitespace(result)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Passes

    private static func removeSoftHyphens(_ text: String) -> String {
        guard text.contains("\u{00AD}") else { return text }
        return text.replacingOccurrences(of: "\u{00AD}", with: "")
    }

    /// Matches `[1]`, `[2, 3]`, `[10-15]`, `[10–15]`.
    private static let bracketedCitationPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\[\d{1,4}(?:\s*[,–-]\s*\d{1,4})*\]"#)
    }()

    private static func removeBracketedCitations(_ text: String) -> String {
        replaceAll(bracketedCitationPattern, in: text, with: "")
    }

    /// Anchored, non-nested-quantifier form (unlike naive author-year regexes)
    /// to avoid catastrophic backtracking. Requires a literal year, so narrative
    /// parentheticals like "(he thought, not for the first time)" survive.
    private static let authorYearCitationPattern: NSRegularExpression = {
        let name = #"[A-Z][a-zA-Z]+"#
        let coauthor = #"(?:\s+et al\.?|\s*(?:&|and)\s*\#(name))?"#
        let group = #"\#(name)\#(coauthor)\s*,\s*(?:19|20)\d{2}"#
        return try! NSRegularExpression(pattern: #"\(\s*\#(group)(?:\s*;\s*\#(group))*\s*\)"#)
    }()

    private static func removeAuthorYearCitations(_ text: String) -> String {
        replaceAll(authorYearCitationPattern, in: text, with: "")
    }

    /// `(see Fig. 4)` / `(Table 2)` parentheticals are dropped entirely; inline
    /// `Fig. 4` / `Tab. 2` are expanded to spoken-friendly "Figure 4" / "Table 2".
    private static let figureTableParenPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\(\s*(?:see\s+)?(?:Fig(?:ure)?|Tab(?:le)?)\.?\s*\d{1,4}\s*\)"#,
            options: .caseInsensitive)
    }()
    private static let inlineFigurePattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\bFig\.\s*(\d{1,4})\b"#)
    }()
    private static let inlineTablePattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\bTab\.\s*(\d{1,4})\b"#)
    }()

    private static func normalizeFigureTableReferences(_ text: String) -> String {
        var result = replaceAll(figureTableParenPattern, in: text, with: "")
        result = replaceAll(inlineFigurePattern, in: result, with: "Figure $1")
        result = replaceAll(inlineTablePattern, in: result, with: "Table $1")
        return result
    }

    /// Removed citations/references can leave doubled spaces or a stray space
    /// before trailing punctuation (e.g. "the result [1] ." -> "the result .").
    private static func collapseWhitespace(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"\s+([.,;:!?])"#, with: "$1", options: .regularExpression)
        return result
    }

    private static func replaceAll(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    // MARK: - Language detection at parse time

    /// Cheap language sample from a handful of substantial paragraphs. Mirrors
    /// `SavedDocument.detectedLanguage`'s (Models.swift) sampling approach, but
    /// runs directly on parser output — a `SavedDocument` doesn't exist yet at
    /// import time.
    static func quickDetectLanguage(chapterParagraphs: [[Paragraph]]) -> String {
        var sampleText = ""
        var count = 0
        outer: for chapter in chapterParagraphs {
            for paragraph in chapter {
                let text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count > 30 else { continue }
                sampleText += text + " "
                count += 1
                if count >= 10 { break outer }
            }
        }
        let trimmed = sampleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "en" }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let language = recognizer.dominantLanguage else { return "en" }
        return String(language.rawValue.prefix(2))
    }
}
