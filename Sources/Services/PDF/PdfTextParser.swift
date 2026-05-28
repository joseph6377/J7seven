import Foundation
import PDFKit
import UIKit

enum PdfTextParserError: LocalizedError {
    case invalidPDF
    case emptyPDF
    
    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "Could not open the PDF document. It may be corrupt or encrypted."
        case .emptyPDF: return "The PDF document contains no readable text content."
        }
    }
}

struct PdfChapter {
    let title: String
    let paragraphs: [Paragraph]
}

@MainActor
enum PdfTextParser {
    
    struct ParsedBook {
        let title: String
        let author: String?
        let slug: String
        let coverData: Data?
        let chapters: [PdfChapter]
        let pageCount: Int
    }
    
    private struct OutlineItem {
        let title: String
        let pageIndex: Int
    }
    
    private struct ChapterAccumulator {
        let title: String
        let startPage: Int
        let endPage: Int
        var paragraphs: [Paragraph] = []
    }
    
    /// Parses a PDF document and extracts its structural text page-by-page.
    static func parse(pdfURL: URL) async throws -> ParsedBook {
        guard let document = PDFDocument(url: pdfURL) else {
            throw PdfTextParserError.invalidPDF
        }
        
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw PdfTextParserError.emptyPDF
        }
        
        // 1. Metadata Extraction
        let titleAttr = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let authorAttr = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
        
        let title = (titleAttr?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? titleAttr!
            : pdfURL.deletingPathExtension().lastPathComponent
        
        let author = (authorAttr?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? authorAttr!
            : "Unknown Author"
        
        let slug = pdfURL.deletingPathExtension().lastPathComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        
        // 2. Render Page 0 Thumbnail Cover
        var coverData: Data? = nil
        if let firstPage = document.page(at: 0) {
            let thumbnail = firstPage.thumbnail(of: CGSize(width: 200, height: 280), for: .trimBox)
            coverData = thumbnail.jpegData(compressionQuality: 0.8)
        }
        
        // 3. Document Pre-pass: Compute repeating Y positions for header/footer detection
        let repeatingYPositions = await computeRepeatingYPositions(document: document)
        
        // 4. Construct Chapter/Outline Ranges
        var outlineItems: [OutlineItem] = []
        if let outlineRoot = document.outlineRoot {
            traverseOutline(outlineRoot, document: document, items: &outlineItems)
        }
        
        // Sort outline items by page index and de-duplicate
        outlineItems.sort { $0.pageIndex < $1.pageIndex }
        var uniqueItems: [OutlineItem] = []
        for item in outlineItems {
            if !uniqueItems.contains(where: { $0.pageIndex == item.pageIndex }) {
                uniqueItems.append(item)
            }
        }
        
        var accumulators: [ChapterAccumulator] = []
        if !uniqueItems.isEmpty {
            for i in 0..<uniqueItems.count {
                let start = (i == 0) ? 0 : uniqueItems[i].pageIndex
                let end = (i == uniqueItems.count - 1) ? pageCount - 1 : uniqueItems[i+1].pageIndex - 1
                accumulators.append(ChapterAccumulator(
                    title: uniqueItems[i].title,
                    startPage: start,
                    endPage: max(start, end)
                ))
            }
        } else {
            // Fallback: one chapter per page
            for pageIdx in 0..<pageCount {
                accumulators.append(ChapterAccumulator(
                    title: "Page \(pageIdx + 1)",
                    startPage: pageIdx,
                    endPage: pageIdx
                ))
            }
        }
        
        // 5. Extraction Loop (Responsive and Cancellable)
        for pageIdx in 0..<pageCount {
            if Task.isCancelled { break }
            guard let page = document.page(at: pageIdx) else { continue }
            
            let paragraphs = await PdfReadingOrderExtractor.extractParagraphs(
                from: page,
                pageNumber: pageIdx + 1,
                repeatingYPositions: repeatingYPositions
            )
            
            if let accIdx = accumulators.firstIndex(where: { pageIdx >= $0.startPage && pageIdx <= $0.endPage }) {
                accumulators[accIdx].paragraphs.append(contentsOf: paragraphs)
            }
            
            await Task.yield() // Keep UI responsive between page parses
        }
        
        // Filter out any chapters that contain no parsed paragraphs
        let finalChapters = accumulators.filter { !$0.paragraphs.isEmpty }.map { acc in
            PdfChapter(title: acc.title, paragraphs: acc.paragraphs)
        }
        
        guard !finalChapters.isEmpty else {
            throw PdfTextParserError.emptyPDF
        }
        
        return ParsedBook(
            title: title,
            author: author,
            slug: slug,
            coverData: coverData,
            chapters: finalChapters,
            pageCount: pageCount
        )
    }
    
    // MARK: - Private Helpers
    
    private static func traverseOutline(_ outline: PDFOutline, document: PDFDocument, items: inout [OutlineItem]) {
        if let label = outline.label, let destination = outline.destination, let page = destination.page {
            let pageIdx = document.index(for: page)
            if pageIdx != NSNotFound {
                items.append(OutlineItem(title: label, pageIndex: pageIdx))
            }
        }
        
        for i in 0..<outline.numberOfChildren {
            if let child = outline.child(at: i) {
                traverseOutline(child, document: document, items: &items)
            }
        }
    }
    
    private static func computeRepeatingYPositions(document: PDFDocument) async -> Set<CGFloat> {
        var yPageMap: [Int: Set<Int>] = [:] // Rounded Y -> Set of page indices
        let pageCount = document.pageCount
        
        for pageIdx in 0..<pageCount {
            if Task.isCancelled { break }
            guard let page = document.page(at: pageIdx) else { continue }
            
            guard let pageSelection = page.selection(for: page.bounds(for: .mediaBox)) else {
                continue
            }
            
            let lines = pageSelection.selectionsByLine()
            let pageHeight = page.bounds(for: .mediaBox).height
            guard pageHeight > 0 else { continue }
            
            for line in lines {
                let bounds = line.bounds(for: page)
                let normY = bounds.midY / pageHeight
                
                // Only register Y positions in the top or bottom margins for repeating detection
                let isHeaderOrFooterArea = normY < 0.15 || normY > 0.85
                guard isHeaderOrFooterArea else { continue }
                
                let roundedY = Int(round(normY * 1000.0)) // 3 decimal places precision
                yPageMap[roundedY, default: Set<Int>()].insert(pageIdx)
            }
            
            if pageIdx % 10 == 0 {
                await Task.yield() // yielding between batches for cooperative multitasking
            }
        }
        
        var repeatingY = Set<CGFloat>()
        for (roundedY, pages) in yPageMap {
            if pages.count >= 3 {
                repeatingY.insert(CGFloat(roundedY) / 1000.0)
            }
        }
        return repeatingY
    }
}
