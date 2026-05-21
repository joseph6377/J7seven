import XCTest
@testable import BooksAppV2

final class ZipExtractorTests: XCTestCase {

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

    func testExtractStoredZip() throws {
        // Base64 for a ZIP file with a stored (uncompressed) 'hello.txt' containing "Hello ZIP!\n"
        let base64StoredZip = "UEsDBAoAAAAAABFgtVycasrjCwAAAAsAAAAJABwAaGVsbG8udHh0VVQJAAOJpg5qiKYOanV4CwABBPUBAAAEFAAAAEhlbGxvIFpJUCEKUEsBAh4DCgAAAAAAEWC1XJxqyuMLAAAACwAAAAkAGAAAAAAAAAAAAKSBAAAAAGhlbGxvLnR4dFVUBQADiaYOanV4CwABBPUBAAAEFAAAAFBLBQYAAAAAAQABAE8AAABOAAAAAAA="
        
        guard let zipData = Data(base64Encoded: base64StoredZip) else {
            XCTFail("Failed to decode base64 ZIP")
            return
        }
        
        let zipURL = tempDirURL.appendingPathComponent("stored.zip")
        try zipData.write(to: zipURL)
        
        let extractDest = tempDirURL.appendingPathComponent("extracted_stored")
        try ZipExtractor.extract(zipURL, to: extractDest)
        
        let extractedFile = extractDest.appendingPathComponent("hello.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedFile.path))
        
        let content = try String(contentsOf: extractedFile, encoding: .utf8)
        XCTAssertEqual(content, "Hello ZIP!\n")
    }

    func testExtractDeflatedZip() throws {
        // Base64 for a ZIP file with a deflated 'deflate.txt' containing 100 repetitions of "Hello Deflate!"
        let base64DeflatedZip = "UEsDBBQAAAAIABJgtVyZBWDUHgAAANwFAAALABwAZGVmbGF0ZS50eHRVVAkAA4umDmqLpg5qdXgLAAEE9QEAAAQUAAAA80jNyclXcElNy0ksSVXk8hjljnJHuaPcUe7Q5wIAUEsBAh4DFAAAAAgAEmC1XJkFYNQeAAAA3AUAAAsAGAAAAAAAAQAAAKSBAAAAAGRlZmxhdGUudHh0VVQFAAOLpg5qdXgLAAEE9QEAAAQUAAAAUEsFBgAAAAABAAEAUQAAAGMAAAAAAA=="
        
        guard let zipData = Data(base64Encoded: base64DeflatedZip) else {
            XCTFail("Failed to decode base64 ZIP")
            return
        }
        
        let zipURL = tempDirURL.appendingPathComponent("deflated.zip")
        try zipData.write(to: zipURL)
        
        let extractDest = tempDirURL.appendingPathComponent("extracted_deflated")
        try ZipExtractor.extract(zipURL, to: extractDest)
        
        let extractedFile = extractDest.appendingPathComponent("deflate.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedFile.path))
        
        let content = try String(contentsOf: extractedFile, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("Hello Deflate!"))
        
        // Should contain 100 lines
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 100)
    }

    func testExtractMalformedZip() {
        let malformedData = Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00]) // Incomplete signature/header
        let zipURL = tempDirURL.appendingPathComponent("malformed.zip")
        try? malformedData.write(to: zipURL)
        
        let extractDest = tempDirURL.appendingPathComponent("extracted_malformed")
        
        XCTAssertThrowsError(try ZipExtractor.extract(zipURL, to: extractDest)) { error in
            XCTAssertEqual(error as? ZipError, ZipError.invalidFormat)
        }
    }
}
