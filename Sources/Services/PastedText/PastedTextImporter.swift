import Foundation

enum PastedTextImporter {
    static let minLength = 20
    static let maxLength = 500_000  // ~80k words; sanity cap
    
    enum ImportError: LocalizedError {
        case tooShort, tooLong, empty
        var errorDescription: String? {
            switch self {
            case .tooShort: return "Text is too short to import (minimum 20 characters)."
            case .tooLong: return "Text exceeds the maximum length of 500,000 characters."
            case .empty:   return "No text to import."
            }
        }
    }
    
    struct ParsedBook {
        let title: String
        let paragraphs: [Paragraph]
    }
    
    static func importText(
        _ raw: String,
        title userTitle: String?
    ) async throws -> ParsedBook {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }
        guard trimmed.count >= minLength else { throw ImportError.tooShort }
        guard trimmed.count <= maxLength else { throw ImportError.tooLong }
        
        // Reuse the web-import TTS normalizer for URL/abbreviation/number cleanup
        let normalized = TtsTextNormalizer.normalize(text: trimmed)
        
        // Paragraph splitting: prefer blank-line boundaries, fall back to single newlines
        let paragraphTexts: [String]
        if normalized.contains("\n\n") {
            paragraphTexts = normalized
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else if normalized.contains("\n") {
            paragraphTexts = normalized
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            // One wall of text — split into ~150-word paragraphs at sentence boundaries
            paragraphTexts = SentenceChunker.chunk(normalized, targetWordCount: 150)
        }
        
        let paragraphs = paragraphTexts.map { Paragraph(text: $0, pageNumber: nil) }
        
        let title = (userTitle?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? deriveTitle(from: trimmed)
        
        return ParsedBook(
            title: title,
            paragraphs: paragraphs
        )
    }
    
    /// First non-empty line, truncated to 60 chars at a word boundary.
    private static func deriveTitle(from text: String) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? "Pasted Text"
        
        if firstLine.count <= 60 { return firstLine }
        let truncated = String(firstLine.prefix(60))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }
}
