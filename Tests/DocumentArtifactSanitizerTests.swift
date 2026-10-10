import XCTest
@testable import BooksAppV2

final class DocumentArtifactSanitizerTests: XCTestCase {

    private func clean(_ text: String, language: String = "en") -> String {
        DocumentArtifactSanitizer.sanitize(text: text, language: language)
    }

    // MARK: - Bracketed citations

    func testBracketedCitationSingleRemoved() {
        XCTAssertEqual(clean("This was shown previously [1] in the literature."),
                       "This was shown previously in the literature.")
    }

    func testBracketedCitationListRemoved() {
        XCTAssertEqual(clean("Several studies [2, 3] agree."), "Several studies agree.")
    }

    func testBracketedCitationRangeWithEnDashRemoved() {
        XCTAssertEqual(clean("As shown [10–15] earlier."), "As shown earlier.")
    }

    // MARK: - Author-year citations (English-gated)

    func testAuthorYearCitationRemoved() {
        XCTAssertEqual(
            clean("This was established (Smith et al., 2023; Doe & Johnson, 2024) previously."),
            "This was established previously.")
    }

    func testNarrativeParentheticalPreserved() {
        let text = "She paused (he thought, not for the first time) before answering."
        XCTAssertEqual(clean(text), text)
    }

    func testAuthorYearRuleSkippedForNonEnglishDocument() {
        let text = "Ceci a été établi (Dupont, 2020) précédemment."
        XCTAssertEqual(clean(text, language: "fr"), text)
    }

    // MARK: - Figure/table references (English-gated)

    func testFigureAbbreviationExpanded() {
        XCTAssertEqual(clean("See Fig. 3 for details."), "See Figure 3 for details.")
    }

    func testTableAbbreviationExpanded() {
        XCTAssertEqual(clean("Results in Tab. 2 show this."), "Results in Table 2 show this.")
    }

    func testFigureParentheticalRemoved() {
        XCTAssertEqual(clean("The trend is clear (see Fig. 4)."), "The trend is clear.")
    }

    // MARK: - Soft hyphens, whitespace, URLs

    func testSoftHyphenRemoved() {
        XCTAssertEqual(clean("hyphen\u{00AD}ated word"), "hyphenated word")
    }

    func testWhitespaceCollapsedAfterRemoval() {
        XCTAssertEqual(clean("Text here [1] , more text."), "Text here, more text.")
    }

    func testURLNormalized() {
        XCTAssertEqual(clean("Visit https://example.com/page for more."),
                       "Visit link to example.com for more.")
    }

    // MARK: - Paragraph-level sanitize drops emptied paragraphs

    func testEmptyParagraphDroppedAfterSanitizing() {
        let paragraphs = [
            Paragraph(text: "[1]", pageNumber: nil),
            Paragraph(text: "Real text.", pageNumber: nil),
        ]
        let sanitized = DocumentArtifactSanitizer.sanitize(paragraphs: paragraphs, language: "en")
        XCTAssertEqual(sanitized.map(\.text), ["Real text."])
    }
}
