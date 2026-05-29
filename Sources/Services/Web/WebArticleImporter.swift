import Foundation

enum ImportProgress: String, CaseIterable, Identifiable {
    case fetching = "Fetching article content..."
    case extracting = "Extracting article body..."
    case cleaning = "Removing ads & navigation..."
    case normalizing = "Normalizing text for reading..."
    case done = "Finished!"
    
    var id: String { rawValue }
}

@MainActor
final class WebArticleImporter {
    
    typealias ParsedBook = WebArticleToParsedBook.ParsedBook
    
    static func importArticle(
        from url: URL,
        htmlContent: String? = nil,
        preRenderedHtml: String? = nil,
        preExtractedJsonLd: [String]? = nil,
        progress: @escaping (ImportProgress) -> Void = { _ in }
    ) async throws -> ParsedBook {
        
        // --- Stage 1: Fetch HTML ---
        let html: String
        if let providedHtml = preRenderedHtml ?? htmlContent {
            print("[WebArticleImporter] Stage 1 skipped: HTML content pre-provided.")
            html = providedHtml
        } else {
            progress(.fetching)
            html = try await HtmlFetcher.fetch(url: url)
        }
        
        // --- Stage 2: JSON-LD Extraction ---
        progress(.extracting)
        var jsonLd: JsonLdArticle? = nil
        if let preExtracted = preExtractedJsonLd, !preExtracted.isEmpty {
            jsonLd = JsonLdExtractor.extract(fromBlocks: preExtracted)
        }
        if jsonLd == nil {
            jsonLd = JsonLdExtractor.extract(html: html)
        }
        
        let parsedBook: ParsedBook
        
        if let jsonLd = jsonLd, jsonLd.articleBody.count > 200 {
            print("[WebArticleImporter] Stage 2 successful: JSON-LD articleBody extracted. Skipping downstream readability stages.")
            
            // --- Stage 5: TTS Normalization ---
            progress(.normalizing)
            let normalizedBody = TtsTextNormalizer.normalize(text: jsonLd.articleBody)
            
            // --- Map to ParsedBook ---
            parsedBook = await WebArticleToParsedBook.map(
                html: html,
                url: url,
                jsonLd: jsonLd,
                readability: nil,
                normalizedText: normalizedBody
            )
        } else {
            print("[WebArticleImporter] Stage 2 skipped or insufficient: Falling back to Readability.")
            
            // --- Stage 3: Readability Extraction ---
            progress(.extracting)
            let readability = try await ReadabilityExtractor.extract(html: html, url: url)
            
            // --- Stage 4: Junk Pattern Stripping ---
            progress(.cleaning)
            let keepCodeBlocks = UserDefaults.standard.bool(forKey: "web.keepCodeBlocks")
            let cleanHtml = try JunkPatternStripper.strip(html: readability.html, keepCodeBlocks: keepCodeBlocks)
            
            // Extract paragraphs from cleaned HTML
            let paragraphs = TtsTextNormalizer.extractParagraphsFromHTML(cleanHtml)
            let bodyText = paragraphs.joined(separator: "\n\n")
            
            // --- Stage 5: TTS Normalization ---
            progress(.normalizing)
            let normalizedBody = TtsTextNormalizer.normalize(text: bodyText)
            
            // --- Map to ParsedBook ---
            parsedBook = await WebArticleToParsedBook.map(
                html: html,
                url: url,
                jsonLd: nil,
                readability: readability,
                normalizedText: normalizedBody
            )
        }
        
        progress(.done)
        return parsedBook
    }
}
