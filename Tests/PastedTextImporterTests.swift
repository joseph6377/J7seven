import XCTest
@testable import BooksAppV2

final class PastedTextImporterTests: XCTestCase {
    
    func testPastedTextImportBasic() async throws {
        let rawText = """
        This is a cool test paragraph. It is long enough to satisfy the character minimum.
        
        This is the second paragraph in our pasted text document. It contains good content.
        """
        
        let parsed = try await PastedTextImporter.importText(rawText, title: "Custom Title")
        
        XCTAssertEqual(parsed.title, "Custom Title")
        XCTAssertEqual(parsed.paragraphs.count, 2)
        XCTAssertEqual(parsed.paragraphs[0].text, "This is a cool test paragraph. It is long enough to satisfy the character minimum.")
        XCTAssertEqual(parsed.paragraphs[1].text, "This is the second paragraph in our pasted text document. It contains good content.")
    }
    
    func testPastedTextAutoTitleDerivation() async throws {
        let rawText = """
        The Rise of Agentic Coding
        Some other text goes here. Let's make sure it contains enough characters to satisfy the minimum count of twenty characters without failing.
        """
        
        let parsed = try await PastedTextImporter.importText(rawText, title: nil)
        XCTAssertEqual(parsed.title, "The Rise of Agentic Coding")
        XCTAssertEqual(parsed.paragraphs.count, 2)
    }
    
    func testPastedTextParagraphFallbacks() async throws {
        // Fallback to single newlines
        let textWithSingleNewlines = """
        Paragraph One is here. We like it very much.
        Paragraph Two is here. We like it too.
        """
        
        let parsedSingle = try await PastedTextImporter.importText(textWithSingleNewlines, title: nil)
        XCTAssertEqual(parsedSingle.paragraphs.count, 2)
        
        // Wall of text with no line breaks - splits into ~150-word paragraphs using SentenceChunker
        var wallOfText = ""
        for i in 1...60 {
            wallOfText += "This is sentence number \(i). "
        }
        
        let parsedWall = try await PastedTextImporter.importText(wallOfText, title: nil)
        XCTAssertTrue(parsedWall.paragraphs.count >= 2)
    }
    
    func testPastedTextImporterValidation() async {
        // Too short
        let shortText = "Too short."
        do {
            _ = try await PastedTextImporter.importText(shortText, title: nil)
            XCTFail("Should have thrown tooShort error")
        } catch PastedTextImporter.ImportError.tooShort {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Empty
        let emptyText = "   "
        do {
            _ = try await PastedTextImporter.importText(emptyText, title: nil)
            XCTFail("Should have thrown empty error")
        } catch PastedTextImporter.ImportError.empty {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testPastedTextTtsNormalizationAndMarkdownStripping() async throws {
        // Paste input with markdown bold and standalone URL
        let rawText = "This is a **premium** text paste with standard currency like $1.2M and date 2026-05-28. Visit https://google.com."
        
        let parsed = try await PastedTextImporter.importText(rawText, title: nil)
        
        let normalizedText = parsed.paragraphs[0].text
        // Check that Markdown has been stripped and values normalized by TtsTextNormalizer
        XCTAssertFalse(normalizedText.contains("**"))
        XCTAssertTrue(normalizedText.contains("premium"))
        XCTAssertTrue(normalizedText.contains("1.2 million dollars"))
        XCTAssertTrue(normalizedText.contains("May 28, 2026"))
        XCTAssertTrue(normalizedText.contains("link to google.com"))
    }
}
