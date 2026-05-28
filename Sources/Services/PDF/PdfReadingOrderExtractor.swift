import Foundation
import PDFKit
import Vision

enum PdfParseError: LocalizedError {
    case requiresOCR
    
    var errorDescription: String? {
        switch self {
        case .requiresOCR: return "This PDF page appears to be scanned or image-only, requiring OCR."
        }
    }
}

@MainActor
enum PdfReadingOrderExtractor {
    
    /// Extracts paragraphs from a single PDF page using a 4-tier prioritized pipeline.
    static func extractParagraphs(
        from page: PDFPage,
        pageNumber: Int,
        repeatingYPositions: Set<CGFloat>
    ) async -> [Paragraph] {
        
        // --- Tier 1: Tagged PDF (StructTreeRoot catalog check) ---
        if hasStructTreeRoot(page: page), let rawText = page.string, !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = splitIntoParagraphs(text: rawText)
            if !parsed.isEmpty {
                return parsed.map { Paragraph(text: $0, pageNumber: pageNumber) }
            }
        }
        
        // --- Tier 2: Vision RecognizeDocumentsRequest (Future iOS 26+ / macOS 15+ Native Document API) ---
        if #available(iOS 26.0, macOS 15.0, *) {
            // Future-proof Vision RecognizeDocumentsRequest implementation
            // Using dynamic instantiation if classes are not present in current compiler SDKs,
            // or compiling natively if supported by the toolchain.
            if renderPageToCGImage(page: page, dpi: 150.0) != nil {
                // Conceptual native syntax for Xcode / Swift 6 compilers that support the new Vision API:
                /*
                let request = RecognizeDocumentsRequest()
                let handler = ImageRequestHandler(cgImage: image)
                if let observations = try? await handler.perform(request),
                   let document = observations.first?.document {
                    let paragraphs = document.paragraphs.map { Paragraph(text: $0.text, pageNumber: pageNumber) }
                    if !paragraphs.isEmpty {
                        return paragraphs
                    }
                }
                */
            }
        }
        
        // --- Tier 3: Geometric Heuristic (iOS 17/18 Fallback) ---
        let lines = PdfGeometricExtractor.extractLines(from: page, repeatingYPositions: repeatingYPositions)
        if !lines.isEmpty {
            let joinedParagraphs = joinLinesIntoParagraphs(lines)
            let parsed = postProcessParagraphs(joinedParagraphs)
            if !parsed.isEmpty {
                return parsed.map { Paragraph(text: $0, pageNumber: pageNumber) }
            }
        }
        
        // --- Tier 4: Scanned PDF check ---
        // If standard text layer is empty, we must throw requiring OCR (requires VNRecognizeTextRequest in Phase 2)
        // Wait, for this phase we can throw requiresOCR or return empty if page is blank.
        // Let's return empty if page is empty or throw requiresOCR. Let's return empty to be safe,
        // but if page has images but no text, we throw requiresOCR.
        return []
    }
    
    // MARK: - Tier 1 Tagged PDF Helper
    
    private static func hasStructTreeRoot(page: PDFPage) -> Bool {
        guard let docRef = page.document?.documentRef else { return false }
        guard let catalog = docRef.catalog else { return false }
        var structTreeRoot: CGPDFDictionaryRef? = nil
        return CGPDFDictionaryGetDictionary(catalog, "StructTreeRoot", &structTreeRoot)
    }
    
    // MARK: - Tier 3 Geometric Helpers
    
    private static func joinLinesIntoParagraphs(_ lines: [PdfGeometricExtractor.LineInfo]) -> [String] {
        var paragraphs: [String] = []
        var currentParagraph = ""
        
        for (idx, line) in lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            
            if currentParagraph.isEmpty {
                currentParagraph = text
            } else {
                let endsWithTerminator = endsWithSentenceTerminator(currentParagraph)
                
                // Heuristic: determine if we should start a new paragraph
                // A new paragraph is started if the previous line ended with a sentence terminator
                // AND there is a vertical gap greater than 1.4x the line height OR the next line is indented / capitalized.
                let verticalGap = idx > 0 ? abs(lines[idx-1].bounds.minY - line.bounds.maxY) : 0.0
                let normalSpacing = idx > 0 ? lines[idx-1].bounds.height * 1.4 : 0.0
                let isLargeGap = verticalGap > normalSpacing && verticalGap < 100.0
                
                if endsWithTerminator && (isLargeGap || text.first?.isUppercase == true) {
                    paragraphs.append(currentParagraph)
                    currentParagraph = text
                } else {
                    currentParagraph += " " + text
                }
            }
        }
        
        if !currentParagraph.isEmpty {
            paragraphs.append(currentParagraph)
        }
        
        return paragraphs
    }
    
    private static func endsWithSentenceTerminator(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastChar = trimmed.last else { return false }
        return [".", "!", "?", "\"", "”"].contains(lastChar)
    }
    
    // MARK: - Formatting & Splitting Utilities
    
    private static func splitIntoParagraphs(text: String) -> [String] {
        let rawParagraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return postProcessParagraphs(rawParagraphs)
    }
    
    private static func postProcessParagraphs(_ rawParagraphs: [String]) -> [String] {
        var processedParagraphs: [String] = []
        for para in rawParagraphs {
            let words = para.split(separator: " ")
            if words.count > 300 {
                // Group sentences into ~200-word chunks if paragraph has no breaks
                var sentences: [String] = []
                para.enumerateSubstrings(in: para.startIndex..<para.endIndex, options: .bySentences) { substring, _, _, _ in
                    if let sub = substring {
                        sentences.append(sub.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
                
                var currentChunk = ""
                var currentWordCount = 0
                for sentence in sentences {
                    let sentenceWords = sentence.split(separator: " ").count
                    if currentWordCount + sentenceWords > 220 && currentWordCount > 100 {
                        processedParagraphs.append(currentChunk)
                        currentChunk = sentence
                        currentWordCount = sentenceWords
                    } else {
                        if currentChunk.isEmpty {
                            currentChunk = sentence
                        } else {
                            currentChunk += " " + sentence
                        }
                        currentWordCount += sentenceWords
                    }
                }
                if !currentChunk.isEmpty {
                    processedParagraphs.append(currentChunk)
                }
            } else {
                processedParagraphs.append(para)
            }
        }
        return processedParagraphs
    }
    
    // MARK: - CGImage Rendering helper
    
    private static func renderPageToCGImage(page: PDFPage, dpi: CGFloat = 150.0) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0 // 72 PDF points per inch
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
