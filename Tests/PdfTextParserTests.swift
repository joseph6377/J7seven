import XCTest
import PDFKit
import UIKit
@testable import BooksAppV2

final class PdfTextParserTests: XCTestCase {
    
    var tempDirURL: URL!
    
    override func setUp() {
        super.setUp()
        tempDirURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let url = tempDirURL {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    /// Programmatically generates a PDF with selectable text layers using UIKit graphics renderers.
    private func createTestPDF(pages: [(rects: [CGRect], strings: [String])], metadata: [String: String] = [:]) -> URL {
        let pdfURL = tempDirURL.appendingPathComponent("test_\(UUID().uuidString).pdf")
        
        let format = UIGraphicsPDFRendererFormat()
        var info: [String: Any] = [:]
        if let title = metadata["Title"] { info[kCGPDFContextTitle as String] = title }
        if let author = metadata["Author"] { info[kCGPDFContextAuthor as String] = author }
        format.documentInfo = info
        
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800), format: format)
        
        try! renderer.writePDF(to: pdfURL) { context in
            for pageData in pages {
                context.beginPage()
                // UIKit draws with top-left origin, PDFKit reads standard printable selections.
                for (rect, text) in zip(pageData.rects, pageData.strings) {
                    let nsText = text as NSString
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12)
                    ]
                    nsText.draw(in: rect, withAttributes: attrs)
                }
            }
        }
        return pdfURL
    }
    
    func testPdfMetadataExtraction() async throws {
        let metadata = ["Title": "Programmatic PDF Title", "Author": "Antigravity Dev"]
        let pdfURL = createTestPDF(pages: [
            (rects: [CGRect(x: 50, y: 50, width: 500, height: 30)], strings: ["Introduction to PDF parsing."])
        ], metadata: metadata)
        
        let parsed = try await PdfTextParser.parse(pdfURL: pdfURL)
        
        XCTAssertEqual(parsed.title, "Programmatic PDF Title")
        XCTAssertEqual(parsed.author, "Antigravity Dev")
        XCTAssertEqual(parsed.pageCount, 1)
        XCTAssertEqual(parsed.chapters.count, 1)
        XCTAssertEqual(parsed.chapters[0].paragraphs.count, 1)
        XCTAssertEqual(parsed.chapters[0].paragraphs[0].text, "Introduction to PDF parsing.")
    }
    
    func testPdfTwoColumnSorting() async throws {
        // Render two columns: Left Column has text, Right Column has text.
        // We write them programmatically. In PDF coordinates:
        // Left column: x=50, top-to-bottom lines.
        // Right column: x=350, top-to-bottom lines.
        let pdfURL = createTestPDF(pages: [
            (
                rects: [
                    CGRect(x: 50, y: 100, width: 200, height: 20),  // Left Col - Line 1
                    CGRect(x: 50, y: 130, width: 200, height: 20),  // Left Col - Line 2
                    CGRect(x: 350, y: 100, width: 200, height: 20), // Right Col - Line 1
                    CGRect(x: 350, y: 130, width: 200, height: 20)  // Right Col - Line 2
                ],
                strings: [
                    "This is left line",
                    "one of left column.",
                    "This is right line",
                    "one of right column."
                ]
            )
        ])
        
        let parsed = try await PdfTextParser.parse(pdfURL: pdfURL)
        XCTAssertEqual(parsed.chapters.count, 1)
        let ch = parsed.chapters[0]
        
        // Due to paragraph reconstruction, it should join column lines:
        XCTAssertGreaterThanOrEqual(ch.paragraphs.count, 2)
        XCTAssertEqual(ch.paragraphs[0].text, "This is left line one of left column.")
        XCTAssertEqual(ch.paragraphs[1].text, "This is right line one of right column.")
    }
    
    func testHeaderFooterStripping() async throws {
        // Draw a repeating header at top (y=20) and footer at bottom (y=750) across 3 pages.
        // Also draw page-specific content on each page at varying Y positions (200, 300, 400).
        let pagesData = (0..<3).map { pageIdx in
            let uniqueY = 200 + (pageIdx * 100)
            return (
                rects: [
                    CGRect(x: 50, y: 20, width: 500, height: 20),   // Header
                    CGRect(x: 50, y: CGFloat(uniqueY), width: 500, height: 20),  // Unique Page Content
                    CGRect(x: 50, y: 750, width: 500, height: 20)   // Footer
                ],
                strings: [
                    "Shared Header Title",
                    "Unique content on page \(pageIdx + 1).",
                    "Page Footer \(pageIdx + 1)"
                ]
            )
        }
        
        let pdfURL = createTestPDF(pages: pagesData)
        let parsed = try await PdfTextParser.parse(pdfURL: pdfURL)
        
        // Since Y=20 and Y=750 repeat on 3 pages, they are stripped.
        // Only the page-specific unique content remains.
        XCTAssertEqual(parsed.chapters.count, 3)
        
        XCTAssertEqual(parsed.chapters[0].paragraphs[0].text, "Unique content on page 1.")
        XCTAssertEqual(parsed.chapters[1].paragraphs[0].text, "Unique content on page 2.")
        XCTAssertEqual(parsed.chapters[2].paragraphs[0].text, "Unique content on page 3.")
        
        // Verify header and footer text are completely absent
        for chapter in parsed.chapters {
            for paragraph in chapter.paragraphs {
                XCTAssertFalse(paragraph.text.contains("Shared Header Title"))
                XCTAssertFalse(paragraph.text.contains("Page Footer"))
            }
        }
    }
}
