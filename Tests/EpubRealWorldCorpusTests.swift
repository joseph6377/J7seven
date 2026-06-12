import XCTest
@testable import BooksAppV2

/// Parses any real EPUB files placed in /tmp/epub-corpus on the host machine.
/// Skips when the corpus directory is absent (e.g. on CI), so this never fails
/// a clean checkout — it exists for local verification against real books.
final class EpubRealWorldCorpusTests: XCTestCase {

    private let corpusDir = URL(fileURLWithPath: "/tmp/epub-corpus", isDirectory: true)

    func testParseRealWorldCorpus() throws {
        let fm = FileManager.default
        let epubs = (try? fm.contentsOfDirectory(at: corpusDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "epub" } ?? []
        try XCTSkipIf(epubs.isEmpty, "No corpus at \(corpusDir.path); skipping real-world EPUB checks")

        for epubURL in epubs {
            do {
                let book = try EpubTextParser.parse(epubURL: epubURL)
                XCTAssertFalse(book.chapters.isEmpty,
                               "\(epubURL.lastPathComponent): no chapters")
                let paragraphCount = book.chapters.reduce(0) { $0 + $1.paragraphs.count }
                XCTAssertGreaterThan(paragraphCount, 20,
                                     "\(epubURL.lastPathComponent): suspiciously little text")
                XCTAssertNotEqual(book.title, "Unknown Title",
                                  "\(epubURL.lastPathComponent): title not extracted")
                print("CORPUS OK: \(epubURL.lastPathComponent) — \"\(book.title)\" by \(book.author), " +
                      "\(book.chapters.count) chapters, \(paragraphCount) paragraphs, " +
                      "cover: \(book.coverData != nil)")
            } catch EpubTextParserError.drmProtected {
                print("CORPUS DRM: \(epubURL.lastPathComponent) correctly reported as DRM-protected")
            } catch {
                XCTFail("\(epubURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
