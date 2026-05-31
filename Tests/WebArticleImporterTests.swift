import XCTest
@testable import BooksAppV2

final class WebArticleImporterTests: XCTestCase {
    
    // MARK: - Stage 1: SPA Heuristics
    
    func testSpaHeuristicDetection() {
        let plainHtml = """
        <html>
        <head><title>Static Article</title></head>
        <body>
        <article>
            <h1>Cool Story</h1>
            <p>This is a long article about something static and beautiful. It contains enough content to pass the length threshold.</p>
            <p>More paragraphs here to make sure it gets over 500 characters so that it does not trigger the SPA length heuristic, which checks the text length of the body to prevent importing blank shells.</p>
            <p>Adding more paragraphs to be absolutely sure we pass the threshold. XcodeGen has built a very robust dependency graph and now our package is fully compiled. This test verifies that typical long news articles are parsed statically via plain URLSession rather than falling back to WKWebView headless rendering.</p>
            <p>Still adding more text to satisfy the 500 character minimum. This sentence is about the audiobook player. LysnBox is a gorgeous iOS audiobook app that performs live, ephemeral streaming text-to-speech without writing temporary audio PCM buffers to local storage. It is built in SwiftUI, follows strict concurrency, and works on iOS 17.0+.</p>
        </article>
        </body>
        </html>
        """
        
        let spaHtml = """
        <html>
        <head>
            <title>React Shell</title>
            <script src="/_next/static/chunks/main.js"></script>
        </head>
        <body>
            <div id="__next">Loading...</div>
        </body>
        </html>
        """
        
        XCTAssertFalse(HtmlFetcher.isSPA(html: plainHtml))
        XCTAssertTrue(HtmlFetcher.isSPA(html: spaHtml))
    }
    
    // MARK: - Stage 2: JSON-LD Extraction
    
    func testJsonLdArticleExtraction() {
        let htmlWithJsonLd = """
        <html>
        <head>
            <script type="application/ld+json">
            {
                "@context": "https://schema.org",
                "@type": "NewsArticle",
                "headline": "AI Audiobook Revolution",
                "articleBody": "This is a super detailed article that contains high quality data and goes on for more than two hundred characters. We want to make sure it bypasses downstream readability, keeping it clean. Let's write some more characters here to make it extra long and exceed the two hundred character threshold easily without any issues. This AI Audiobook Revolution is amazing.",
                "author": {
                    "@type": "Person",
                    "name": "Jane Doe"
                },
                "image": [
                    "https://example.com/cover.jpg"
                ]
            }
            </script>
        </head>
        <body>
            <h1>Main Title</h1>
        </body>
        </html>
        """
        
        let extracted = JsonLdExtractor.extract(html: htmlWithJsonLd)
        XCTAssertNotNil(extracted)
        XCTAssertEqual(extracted?.headline, "AI Audiobook Revolution")
        XCTAssertEqual(extracted?.authorName, "Jane Doe")
        XCTAssertEqual(extracted?.imageUrl, "https://example.com/cover.jpg")
        XCTAssertTrue(extracted!.articleBody.contains("Revolution"))
    }
    
    // MARK: - Stage 4: Junk Stripping & Footnote Merging
    
    func testJunkStripperAndFootnotes() throws {
        let inputHtml = """
        <html>
        <body>
            <p>Some clean paragraph that has a footnote ref<sup>[1]</sup> in it.</p>
            <aside class="footnote" id="1">This is the footnote content.</aside>
            
            <form class="newsletter-signup">
                <input type="email" name="email"/>
                <button>Subscribe to our newsletter join</button>
            </form>
            
            <div class="social-share-buttons">
                <a href="https://twitter.com/share">Twitter</a>
                <a href="https://facebook.com/share">Facebook</a>
                <a href="https://linkedin.com/share">LinkedIn</a>
            </div>
            
            <math alttext="two plus two equals four">
                <mn>2</mn><mo>+</mo><mn>2</mn><mo>=</mo><mn>4</mn>
            </math>
            
            <blockquote class="pullquote">This is a duplicate pullquote</blockquote>
        </body>
        </html>
        """
        
        let cleaned = try JunkPatternStripper.strip(html: inputHtml, keepCodeBlocks: false)
        
        // Assertions
        XCTAssertTrue(cleaned.contains("Footnote: This is the footnote content."))
        XCTAssertTrue(cleaned.contains("two plus two equals four"))
        XCTAssertFalse(cleaned.contains("Subscribe to our newsletter"))
        XCTAssertFalse(cleaned.contains("Twitter"))
        XCTAssertFalse(cleaned.contains("pullquote"))
    }
    
    // MARK: - Stage 5: TTS Normalization
    
    func testTtsNormalization() {
        let urlText = "Visit https://google.com for info (https://yahoo.com)."
        let normalizedUrls = TtsTextNormalizer.normalizeURLs(urlText)
        XCTAssertEqual(normalizedUrls, "Visit link to google.com for info .")
        
        let currencyText = "We raised $1.2M and spent $500K on the first $100."
        let normalizedCurrencies = TtsTextNormalizer.normalizeCurrencies(currencyText)
        XCTAssertEqual(normalizedCurrencies, "We raised 1.2 million dollars and spent 500 thousand dollars on the first 100 dollars.")
        
        let dateText = "The release date is 2026-05-28."
        let normalizedDates = TtsTextNormalizer.normalizeDates(dateText)
        XCTAssertTrue(normalizedDates.contains("May 28, 2026"))
        
        let acronymText = "FBI agent met CIA in LLM space."
        let normalizedAcronyms = TtsTextNormalizer.formatInitialisms(acronymText)
        XCTAssertEqual(normalizedAcronyms, "F.B.I. agent met C.I.A. in L.L.M. space.")
        
        let markdownText = "This has **bold** and _italic_ and `code` with [link](https://test.com)."
        let cleanMarkdown = TtsTextNormalizer.stripMarkdown(markdownText)
        XCTAssertEqual(cleanMarkdown, "This has bold and italic and code with link.")
    }
}
