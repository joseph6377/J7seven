import XCTest
@testable import BooksAppV2

/// Coverage for real-world EPUB variations: encoded hrefs, malformed markup,
/// container/OPF quirks, DRM detection, encodings, and zip edge cases.
final class EpubRobustnessTests: XCTestCase {

    var tempDirURL: URL!

    override func setUp() {
        super.setUp()
        let fm = FileManager.default
        tempDirURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? fm.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let url = tempDirURL {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }

    private func parse(_ builder: EpubFixtureBuilder, file: String = "book.epub",
                       forceZip64: Bool = false) throws -> EpubTextParser.ParsedBook {
        let url = tempDirURL.appendingPathComponent(file)
        try builder.write(to: url, forceZip64: forceZip64)
        return try EpubTextParser.parse(epubURL: url)
    }

    private func singleChapterBook(
        href: String = "chapter1.xhtml",
        mediaType: String = "application/xhtml+xml",
        fileName: String? = nil,
        body: String = "<p>Hello world paragraph.</p>"
    ) -> EpubFixtureBuilder {
        EpubFixtureBuilder.standardBook(
            manifestItems: [(id: "c1", href: href, mediaType: mediaType, properties: nil)],
            spine: [(idref: "c1", linear: true)],
            chapterFiles: [fileName ?? href: EpubFixtureBuilder.xhtml(body: body)]
        )
    }

    // MARK: - Href and spine variations

    func testPercentEncodedHref() throws {
        let book = try parse(singleChapterBook(href: "Chapter%201.xhtml", fileName: "Chapter 1.xhtml"))
        XCTAssertEqual(book.chapters.count, 1)
        XCTAssertEqual(book.chapters[0].paragraphs[0].text, "Hello world paragraph.")
    }

    func testTextHtmlSpineItemIncluded() throws {
        let book = try parse(singleChapterBook(href: "c1.html", mediaType: "text/html"))
        XCTAssertEqual(book.chapters.count, 1)
    }

    func testHtmlExtensionWithBogusMediaType() throws {
        let book = try parse(singleChapterBook(href: "c1.xhtml", mediaType: "text/plain"))
        XCTAssertEqual(book.chapters.count, 1)
    }

    func testNonLinearSpineItemsKept() throws {
        let builder = EpubFixtureBuilder.standardBook(
            manifestItems: [
                (id: "c1", href: "c1.xhtml", mediaType: "application/xhtml+xml", properties: nil),
                (id: "c2", href: "c2.xhtml", mediaType: "application/xhtml+xml", properties: nil),
            ],
            spine: [(idref: "c1", linear: false), (idref: "c2", linear: true)],
            chapterFiles: [
                "c1.xhtml": EpubFixtureBuilder.xhtml(body: "<p>Preface text.</p>"),
                "c2.xhtml": EpubFixtureBuilder.xhtml(body: "<p>Main text.</p>"),
            ]
        )
        let book = try parse(builder)
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters[0].paragraphs[0].text, "Preface text.")
    }

    func testCaseMismatchedChapterFilename() throws {
        let book = try parse(singleChapterBook(href: "chapter1.xhtml", fileName: "Chapter1.XHTML"))
        XCTAssertEqual(book.chapters.count, 1)
    }

    // MARK: - Markup variations

    func testDivOnlyChapter() throws {
        let body = "<div>First div paragraph.</div><div><div>Nested div paragraph.</div></div>"
        let book = try parse(singleChapterBook(body: body))
        XCTAssertEqual(book.chapters[0].paragraphs.map(\.text),
                       ["First div paragraph.", "Nested div paragraph."])
    }

    func testListAndBlockquoteChapter() throws {
        let body = "<ul><li>Item one.</li><li>Item two.</li></ul><blockquote>A quote.</blockquote>"
        let book = try parse(singleChapterBook(body: body))
        XCTAssertEqual(book.chapters[0].paragraphs.map(\.text),
                       ["Item one.", "Item two.", "A quote."])
    }

    func testHeadingOnlyChapterUsesHeadings() throws {
        let body = "<h2>Part One</h2>"
        let book = try parse(singleChapterBook(body: body))
        XCTAssertEqual(book.chapters[0].paragraphs.map(\.text), ["Part One"])
    }

    func testHeadingsSkippedWhenParagraphsExist() throws {
        let body = "<h1>Chapter Title</h1><p>Real text.</p>"
        let book = try parse(singleChapterBook(body: body))
        XCTAssertEqual(book.chapters[0].paragraphs.map(\.text), ["Real text."])
    }

    func testDropCapInlineSpanKeepsReadingOrder() throws {
        // A drop-cap span must join seamlessly with the following text, not get
        // reordered to the end: "<span>I</span>n 1862" -> "In 1862".
        let data = Data(EpubFixtureBuilder.xhtml(
            body: "<p><span class=\"dropcap\">I</span>n 1862 when X.</p>").utf8)
        XCTAssertEqual(ChapterTextExtractor.extract(from: data).map(\.text), ["In 1862 when X."])
    }

    func testInlineEmphasisSpacingPreserved() throws {
        let data = Data(EpubFixtureBuilder.xhtml(
            body: "<p>Hello <em>brave</em> world</p>").utf8)
        XCTAssertEqual(ChapterTextExtractor.extract(from: data).map(\.text), ["Hello brave world"])
    }

    func testMalformedChapterRescuedBySwiftSoup() throws {
        // Unclosed <p>, raw ampersand, HTML-only entity: strict XML parsing aborts.
        let html = """
        <html><body>
        <p>Caf&eacute; first paragraph
        <p>Fish & chips second paragraph</p>
        </body></html>
        """
        let builder = EpubFixtureBuilder.standardBook(
            manifestItems: [(id: "c1", href: "c1.xhtml", mediaType: "application/xhtml+xml", properties: nil)],
            spine: [(idref: "c1", linear: true)],
            chapterFiles: ["c1.xhtml": html]
        )
        let book = try parse(builder)
        let allText = book.chapters[0].paragraphs.map(\.text).joined(separator: " ")
        XCTAssertTrue(allText.contains("Café first paragraph"), "got: \(allText)")
        XCTAssertTrue(allText.contains("Fish & chips second paragraph"), "got: \(allText)")
    }

    // MARK: - Container / OPF variations

    func testUppercaseContainerPath() throws {
        let builder = EpubFixtureBuilder.standardBook(
            containerPath: "META-INF/CONTAINER.XML",
            manifestItems: [(id: "c1", href: "c1.xhtml", mediaType: "application/xhtml+xml", properties: nil)],
            spine: [(idref: "c1", linear: true)],
            chapterFiles: ["c1.xhtml": EpubFixtureBuilder.xhtml(body: "<p>Text.</p>")]
        )
        XCTAssertEqual(try parse(builder).chapters.count, 1)
    }

    func testMissingContainerFallsBackToOPFScan() throws {
        var builder = EpubFixtureBuilder()
        builder.addFile("mimetype", "application/epub+zip")
        builder.addFile("OEBPS/content.opf", """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Containerless</dc:title>
          </metadata>
          <manifest>
            <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="c1"/></spine>
        </package>
        """)
        builder.addFile("OEBPS/c1.xhtml", EpubFixtureBuilder.xhtml(body: "<p>Found me.</p>"))
        let book = try parse(builder)
        XCTAssertEqual(book.title, "Containerless")
        XCTAssertEqual(book.chapters.count, 1)
    }

    func testLeadingSlashFullPath() throws {
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="/OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let builder = EpubFixtureBuilder.standardBook(
            containerXML: container,
            manifestItems: [(id: "c1", href: "c1.xhtml", mediaType: "application/xhtml+xml", properties: nil)],
            spine: [(idref: "c1", linear: true)],
            chapterFiles: ["c1.xhtml": EpubFixtureBuilder.xhtml(body: "<p>Text.</p>")]
        )
        XCTAssertEqual(try parse(builder).chapters.count, 1)
    }

    func testMultipleRootfilesPrefersPackageMediaType() throws {
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="alt/renditions.pdf" media-type="application/pdf"/>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let builder = EpubFixtureBuilder.standardBook(
            containerXML: container,
            manifestItems: [(id: "c1", href: "c1.xhtml", mediaType: "application/xhtml+xml", properties: nil)],
            spine: [(idref: "c1", linear: true)],
            chapterFiles: ["c1.xhtml": EpubFixtureBuilder.xhtml(body: "<p>Text.</p>")]
        )
        XCTAssertEqual(try parse(builder).chapters.count, 1)
    }

    // MARK: - DRM

    func testAdobeEncryptedContentThrowsDRMError() throws {
        let encryption = """
        <?xml version="1.0"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
            <EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
            <CipherData><CipherReference URI="OEBPS/c1.xhtml"/></CipherData>
          </EncryptedData>
        </encryption>
        """
        var builder = singleChapterBook(href: "c1.xhtml")
        builder.addFile("META-INF/encryption.xml", encryption)
        XCTAssertThrowsError(try parse(builder)) { error in
            XCTAssertEqual(error as? EpubTextParserError, .drmProtected)
        }
    }

    func testFontObfuscationOnlyIsNotDRM() throws {
        let encryption = """
        <?xml version="1.0"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
            <EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
            <CipherData><CipherReference URI="OEBPS/fonts/main.otf"/></CipherData>
          </EncryptedData>
        </encryption>
        """
        var builder = singleChapterBook(href: "chapter1.xhtml")
        builder.addFile("META-INF/encryption.xml", encryption)
        XCTAssertEqual(try parse(builder).chapters.count, 1)
    }

    // MARK: - Cover

    func testEpub3CoverImageProperty() throws {
        var builder = EpubFixtureBuilder.standardBook(
            manifestItems: [
                (id: "c1", href: "c1.xhtml", mediaType: "application/xhtml+xml", properties: nil),
                (id: "img", href: "images/art.jpg", mediaType: "image/jpeg", properties: "cover-image"),
            ],
            spine: [(idref: "c1", linear: true)],
            chapterFiles: ["c1.xhtml": EpubFixtureBuilder.xhtml(body: "<p>Text.</p>")]
        )
        let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])
        builder.addFile("OEBPS/images/art.jpg", data: fakeJPEG)
        let book = try parse(builder)
        XCTAssertEqual(book.coverData, fakeJPEG)
    }

    // MARK: - XMLIndexer encodings

    func testUTF16LEDocument() throws {
        let xml = "<?xml version=\"1.0\"?><root><item>héllo</item></root>"
        var data = Data([0xFF, 0xFE])
        data.append(xml.data(using: .utf16LittleEndian)!)
        let root = XMLIndexer(data: data)
        XCTAssertEqual(root.child("root")?.child("item")?.text, "héllo")
    }

    func testWindows1252DeclaredEncoding() throws {
        var data = Data("<?xml version=\"1.0\" encoding=\"windows-1252\"?><root><item>caf".utf8)
        data.append(0xE9) // é in windows-1252, invalid as standalone UTF-8
        data.append(Data("</item></root>".utf8))
        let root = XMLIndexer(data: data)
        XCTAssertEqual(root.child("root")?.child("item")?.text, "café")
    }

    func testTruncatedDocumentReportsFailureWithPartialTree() throws {
        let root = XMLIndexer(data: Data("<root><item>text".utf8))
        XCTAssertFalse(root.parseSucceeded)
        XCTAssertNotNil(root.child("root"))
    }

    func testExpandedEntityTable() throws {
        let root = XMLIndexer(data: Data("<r>caf&eacute; &Omega; &le; &amp;</r>".utf8))
        XCTAssertEqual(root.child("r")?.text, "café Ω ≤ &")
    }

    // MARK: - ZipExtractor edge cases

    func testZip64ArchiveExtracts() throws {
        let zipURL = tempDirURL.appendingPathComponent("z64.epub")
        try singleChapterBook().write(to: zipURL, forceZip64: true)
        let out = tempDirURL.appendingPathComponent("z64out")
        try ZipExtractor.extract(zipURL, to: out)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: out.appendingPathComponent("OEBPS/chapter1.xhtml").path))

        let book = try parse(singleChapterBook(), file: "z64book.epub", forceZip64: true)
        XCTAssertEqual(book.chapters.count, 1)
    }

    func testCP437FilenameDecodes() throws {
        var builder = EpubFixtureBuilder()
        var nameBytes = Data("ch".utf8)
        nameBytes.append(0x82) // é in CP437
        nameBytes.append(Data(".txt".utf8))
        builder.addRawEntry(nameBytes: nameBytes, content: Data("hello".utf8), utf8Flag: false)
        let zipURL = tempDirURL.appendingPathComponent("cp437.zip")
        try builder.write(to: zipURL)
        let out = tempDirURL.appendingPathComponent("cp437out")
        try ZipExtractor.extract(zipURL, to: out)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent("ché.txt").path))
    }

    func testCorruptEntryDoesNotAbortArchive() throws {
        var builder = EpubFixtureBuilder()
        builder.addFile("first.txt", "first")
        builder.addFile("second.txt", "second")
        var zip = builder.zipData()
        zip[0] = 0xFF // corrupt the first entry's local header signature
        let zipURL = tempDirURL.appendingPathComponent("corrupt.zip")
        try zip.write(to: zipURL)
        let out = tempDirURL.appendingPathComponent("corruptout")
        try ZipExtractor.extract(zipURL, to: out)
        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: out.appendingPathComponent("first.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("second.txt").path))
    }

    // MARK: - Spoken-title dedup

    private func para(_ s: String) -> Paragraph { Paragraph(text: s, pageNumber: nil) }

    func testSpokenTitleStripsSplitEmbeddedTitle() {
        // Book embeds the chapter number and name as two separate body lines.
        let ct = ChapterText.withSpokenTitle(
            index: 0, title: "1. A Painter Prince",
            paragraphs: [para("1"), para("A Painter Prince"), para("In 1862 when Ravi Varma...")])
        XCTAssertEqual(ct.paragraphs.map(\.text),
                       ["1. A Painter Prince", "In 1862 when Ravi Varma..."])
    }

    func testSpokenTitleStripsNameOnlyEmbeddedTitle() {
        // Body embeds only the title name, without the leading chapter number.
        let ct = ChapterText.withSpokenTitle(
            index: 0, title: "1. A Painter Prince",
            paragraphs: [para("A Painter Prince"), para("Body text here.")])
        XCTAssertEqual(ct.paragraphs.map(\.text), ["1. A Painter Prince", "Body text here."])
    }

    func testSpokenTitleDoesNotOverStripPartialOverlap() {
        // A body line that merely shares a word with the title must be kept.
        let ct = ChapterText.withSpokenTitle(
            index: 0, title: "A Painter Prince",
            paragraphs: [para("A storm was coming."), para("More text.")])
        XCTAssertEqual(ct.paragraphs.map(\.text),
                       ["A Painter Prince", "A storm was coming.", "More text."])
    }

    func testSpokenTitleExactMatchNotDuplicated() {
        let ct = ChapterText.withSpokenTitle(
            index: 0, title: "Prologue", paragraphs: [para("Prologue"), para("It began...")])
        XCTAssertEqual(ct.paragraphs.map(\.text), ["Prologue", "It began..."])
    }

    func testZipSlipEntrySkipped() throws {
        var builder = EpubFixtureBuilder()
        builder.addFile("safe.txt", "safe")
        // Nested entry mirrors real EPUB layout (OEBPS/...). The zip-slip guard must
        // not reject legitimate nested entries — a regression here skipped *every*
        // entry on-device (path-prefix check vs symlink-resolved destination).
        builder.addFile("OEBPS/sub/content.opf", "package")
        builder.addRawEntry(nameBytes: Data("../evil.txt".utf8),
                            content: Data("evil".utf8), utf8Flag: true)
        builder.addRawEntry(nameBytes: Data("/abs/evil.txt".utf8),
                            content: Data("evil".utf8), utf8Flag: true)
        let zipURL = tempDirURL.appendingPathComponent("slip.zip")
        try builder.write(to: zipURL)
        let out = tempDirURL.appendingPathComponent("slipout", isDirectory: true)
        try ZipExtractor.extract(zipURL, to: out)
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("safe.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("OEBPS/sub/content.opf").path),
                      "legitimate nested entry must extract")
        XCTAssertFalse(fm.fileExists(
            atPath: out.deletingLastPathComponent().appendingPathComponent("evil.txt").path),
            "../ traversal must be blocked")
    }
}
