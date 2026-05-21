import XCTest
@testable import BooksAppV2

final class LibraryServiceTests: XCTestCase {

    var libraryService: LibraryService!
    var testDocID: UUID!

    override func setUp() {
        super.setUp()
        libraryService = LibraryService()
        testDocID = UUID()
    }

    override func tearDown() {
        // Clean up our specific test document
        if let id = testDocID {
            libraryService.deleteDocument(id: id)
        }
        super.tearDown()
    }

    func testSaveLoadAndDeleteDocument() {
        let doc = SavedDocument(
            id: testDocID,
            title: "Unit Test Book Title",
            author: "Unit Test Author",
            coverImageData: nil,
            importedAt: Date(),
            lastOpenedAt: Date(),
            chapters: [
                ChapterText(index: 0, title: "Chapter 1", paragraphs: ["Para 1", "Para 2"]),
                ChapterText(index: 1, title: "Chapter 2", paragraphs: ["Para 3"])
            ],
            cursor: PlaybackCursor(chapterIndex: 0, paragraphIndex: 1)
        )
        
        // Save
        libraryService.saveDocument(doc)
        
        // Load
        let loaded = libraryService.loadDocument(id: testDocID)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.title, "Unit Test Book Title")
        XCTAssertEqual(loaded?.author, "Unit Test Author")
        XCTAssertEqual(loaded?.chapters.count, 2)
        XCTAssertEqual(loaded?.cursor.chapterIndex, 0)
        XCTAssertEqual(loaded?.cursor.paragraphIndex, 1)
        
        // Scan library
        let entries = libraryService.scanLocalLibrary()
        let matchingEntry = entries.first { $0.id == testDocID }
        XCTAssertNotNil(matchingEntry)
        XCTAssertEqual(matchingEntry?.title, "Unit Test Book Title")
        XCTAssertEqual(matchingEntry?.author, "Unit Test Author")
        
        // Delete
        libraryService.deleteDocument(id: testDocID)
        
        // Verify gone
        let loadedAfterDelete = libraryService.loadDocument(id: testDocID)
        XCTAssertNil(loadedAfterDelete)
    }

    func testLibraryEntryProgressCalculation() {
        let doc = SavedDocument(
            id: testDocID,
            title: "Progress Book",
            author: "Author",
            coverImageData: nil,
            importedAt: Date(),
            lastOpenedAt: Date(),
            chapters: [
                ChapterText(index: 0, title: "Ch 1", paragraphs: ["P1", "P2"]),
                ChapterText(index: 1, title: "Ch 2", paragraphs: ["P3", "P4", "P5"])
            ],
            cursor: PlaybackCursor(chapterIndex: 1, paragraphIndex: 1) // 3 paragraphs before, total 5
        )
        
        let entry = LibraryEntry(from: doc)
        
        // 3 paragraphs out of 5 is 60% progress (0.6)
        XCTAssertEqual(entry.progress, 0.6, accuracy: 0.01)
    }

    func testLibraryEntryEstimatedTimeLeft() {
        // Constructing a document with enough words to verify speech speed calculation
        // 150 WPM average speaking speed
        // Let's add exactly 300 words to remaining reading content, which should equal exactly 2.0 minutes (2 mins left)
        let paragraphText = Array(repeating: "word", count: 300).joined(separator: " ")
        
        let doc = SavedDocument(
            id: testDocID,
            title: "Time Book",
            author: "Author",
            coverImageData: nil,
            importedAt: Date(),
            lastOpenedAt: Date(),
            chapters: [
                ChapterText(index: 0, title: "Ch 1", paragraphs: [paragraphText])
            ],
            cursor: PlaybackCursor(chapterIndex: 0, paragraphIndex: 0)
        )
        
        let entry = LibraryEntry(from: doc)
        XCTAssertEqual(entry.estimatedTimeLeft, "2 mins left")
    }
}
