import Foundation
import PDFKit

@MainActor
enum PdfGeometricExtractor {
    
    struct LineInfo {
        let selection: PDFSelection
        let bounds: CGRect
        let text: String
    }
    
    /// Extracts lines from a PDF page, sorts them in logical reading order (left-to-right columns, top-to-bottom lines),
    /// and filters out repeating Y positions representing headers and footers.
    static func extractLines(from page: PDFPage, repeatingYPositions: Set<CGFloat>) -> [LineInfo] {
        guard let pageSelection = page.selection(for: page.bounds(for: .mediaBox)) else {
            return []
        }
        
        let lineSelections = pageSelection.selectionsByLine()
        let pageBounds = page.bounds(for: .mediaBox)
        let pageHeight = pageBounds.height
        let pageWidth = pageBounds.width
        
        guard pageHeight > 0 else { return [] }
        
        var lines: [LineInfo] = []
        for selection in lineSelections {
            let bounds = selection.bounds(for: page)
            guard let text = selection.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            
            // 4. Filter lines that appear in repeatingYPositions (header/footer removal in margins only)
            let normY = bounds.midY / pageHeight
            let isHeaderOrFooterArea = normY < 0.15 || normY > 0.85
            if isHeaderOrFooterArea {
                let isRepeating = repeatingYPositions.contains { abs($0 - normY) < 0.005 }
                if isRepeating {
                    continue
                }
            }
            
            lines.append(LineInfo(selection: selection, bounds: bounds, text: text))
        }
        
        // 2. Cluster into columns by x midpoint using a 20% gap threshold
        let gapThreshold = pageWidth * 0.20
        
        // Sort lines by midX to partition them into columns easily
        let sortedByX = lines.sorted { $0.bounds.midX < $1.bounds.midX }
        
        var columns: [[LineInfo]] = []
        var currentColumn: [LineInfo] = []
        
        for line in sortedByX {
            if currentColumn.isEmpty {
                currentColumn.append(line)
            } else {
                let lastMidX = currentColumn.last!.bounds.midX
                if line.bounds.midX - lastMidX > gapThreshold {
                    columns.append(currentColumn)
                    currentColumn = [line]
                } else {
                    currentColumn.append(line)
                }
            }
        }
        if !currentColumn.isEmpty {
            columns.append(currentColumn)
        }
        
        // 3. Sort top-to-bottom (descending Y in PDF coordinates) within each column
        for i in 0..<columns.count {
            columns[i].sort { $0.bounds.midY > $1.bounds.midY }
        }
        
        // Flatten columns (left columns read entirely before right columns)
        let orderedLines = columns.flatMap { $0 }
        return orderedLines
    }
}
