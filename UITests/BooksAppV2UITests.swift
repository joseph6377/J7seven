import XCTest

@MainActor
final class BooksAppV2UITests: XCTestCase {
    
    private var app: XCUIApplication!
    
    override func setUpWithError() throws {
        // Stop immediately when a failure occurs
        continueAfterFailure = false
        
        app = XCUIApplication()
        // Inject our bypass onboarding launch argument!
        app.launchArguments.append("-SkipOnboarding")
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testChapterPickerDrawerAndTextScrolling() throws {
        // 1. Verify Library view is displayed
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5), "Library screen navigation bar should exist.")
        
        // 2. Select first available book card on shelf
        // Look for buttons starting with "book_cell_"
        let bookCellPredicate = NSPredicate(format: "identifier BEGINSWITH 'book_cell_'")
        let bookCells = app.buttons.containing(bookCellPredicate)
        
        XCTAssertGreaterThan(bookCells.count, 0, "There must be at least one book/document on the simulator shelf for UI tests.")
        
        let firstBook = bookCells.element(boundBy: 0)
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5), "First book cell should exist.")
        
        // Tap the book to open the player
        firstBook.tap()
        
        // 3. Confirm Reader Player canvas is loaded
        let playPauseButton = app.buttons["player_play_pause_button"]
        XCTAssertTrue(playPauseButton.waitForExistence(timeout: 8), "Reader Player canvas should be presented (Play/Pause button must exist).")
        
        // 4. Test Play/Pause toggling
        // Let's tap play pause to pause or play
        playPauseButton.tap()
        
        // 5. Open Chapter Picker Drawer
        let chaptersButton = app.buttons["player_chapters_button"]
        XCTAssertTrue(chaptersButton.exists, "Chapters drawer trigger button should be visible.")
        chaptersButton.tap()
        
        // Verify Chapter picker drawer loads
        let chaptersNavBar = app.navigationBars["Chapters"]
        XCTAssertTrue(chaptersNavBar.waitForExistence(timeout: 5), "Chapters picker drawer sheet should be presented.")
        
        // 6. Select a chapter (e.g. Chapter 2 if exists, or tap index 0 / index 1)
        // Let's look for chapter rows
        let chapterRowPredicate = NSPredicate(format: "identifier BEGINSWITH 'chapter_row_'")
        let chapterRows = app.buttons.containing(chapterRowPredicate)
        XCTAssertGreaterThan(chapterRows.count, 0, "There should be at least one chapter listed in the drawer.")
        
        // If there are multiple chapters, tap chapter 2, else tap chapter 1
        let chapterToTap = chapterRows.count > 1 ? app.buttons["chapter_row_1"] : app.buttons["chapter_row_0"]
        XCTAssertTrue(chapterToTap.exists, "Target chapter row should exist.")
        chapterToTap.tap()
        
        // Confirm chapter picker dismissed and player returned
        XCTAssertFalse(chaptersNavBar.exists, "Chapters drawer should dismiss after selecting a chapter.")
        
        // 7. Verify Paragraph Scroll & Visible Bounding Box Coordinates
        // The first paragraph of the active chapter should be shown
        // Since firstIsTitle can exclude paragraph_row_0, let's dynamically query for any visible paragraph rows on screen.
        let paragraphPredicate = NSPredicate(format: "identifier BEGINSWITH 'paragraph_row_'")
        let paragraphs = app.staticTexts.containing(paragraphPredicate)
        
        XCTAssertGreaterThan(paragraphs.count, 0, "There should be at least one paragraph displayed on screen.")
        
        let firstPara = paragraphs.element(boundBy: 0)
        XCTAssertTrue(firstPara.waitForExistence(timeout: 5), "Active paragraph should exist on screen.")
        
        // Let's verify that the paragraph's frame is fully contained within the visible simulator window bounds
        let windowFrame = app.windows.firstMatch.frame
        let paraFrame = firstPara.frame
        
        // Print frames to trace coordinates in test logs
        print("Simulator Window Frame: \(windowFrame)")
        print("Paragraph Frame: \(paraFrame)")
        
        // Assert that the bounding box is fully contained within the window
        // (x must be >= 0, y must be >= 0, x+width <= windowWidth, y+height <= windowHeight)
        XCTAssertTrue(windowFrame.contains(paraFrame), "Paragraph frame \(paraFrame) is not fully contained within the visible simulator window bounds \(windowFrame).")
    }
    
    func testSafariShare() throws {
        // 1. Open URL in Safari on the booted simulator using xcrun simctl from the test runner context,
        // or let's assume it was opened beforehand (or we open it by launching Safari).
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        
        // Wait for Safari to load
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        
        // 2. Find and tap the Safari More Menu button to open Safari menu.
        let moreButton = safari.buttons["MoreMenuButton"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 10), "Safari More Menu button should exist.")
        moreButton.tap()
        
        // 3. Find and tap the native "Share" button using its unique identifier.
        let shareButton = safari.buttons["ShareButton"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 10), "Safari Share button should exist.")
        shareButton.tap()
        
        // 4. Locate the LysnBox cell in the share sheet.
        let lysnboxCell = safari.cells["LysnBox"]
        XCTAssertTrue(lysnboxCell.waitForExistence(timeout: 15), "LysnBox option should appear in Safari Share Sheet.")
        lysnboxCell.tap()
        
        // 5. Verify that LysnBox is opened
        let lysnboxApp = XCUIApplication(bundleIdentifier: "in.josepht.booksappv2")
        XCTAssertTrue(lysnboxApp.wait(for: .runningForeground, timeout: 15), "LysnBox app should launch and come to the foreground.")
        
        // Let it run for a few seconds to process the import
        Thread.sleep(forTimeInterval: 5)
    }
}
