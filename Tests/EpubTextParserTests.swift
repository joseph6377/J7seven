import XCTest
@testable import BooksAppV2

final class EpubTextParserTests: XCTestCase {

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

    func testParseValidEpub() throws {
        // Base64 of a minimal valid EPUB book containing Metadata, Manifest, Spine, and 2 Chapters
        let base64Epub = "UEsDBAoAAAAAABVgtVxvYassFAAAABQAAAAIABwAbWltZXR5cGVVVAkAA5KmDmqSpg5qdXgLAAEE9QEAAAQUAAAAYXBwbGljYXRpb24vZXB1Yit6aXBQSwMECgAAAAAAFWC1XAAAAAAAAAAAAAAAAAkAHABNRVRBLUlORi9VVAkAA5KmDmqSpg5qdXgLAAEE9QEAAAQUAAAAUEsDBAoAAAAAABVgtVwWtbPc/AAAAPwAAAAWABwATUVUQS1JTkYvY29udGFpbmVyLnhtbFVUCQADkqYOapKmDmp1eAsAAQT1AQAABBQAAAA8P3htbCB2ZXJzaW9uPSIxLjAiIGVuY29kaW5nPSJVVEYtOCI/Pgo8Y29udGFpbmVyIHZlcnNpb249IjEuMCIgeG1sbnM9InVybjpvYXNpczpuYW1lczp0YzpvcGVuZG9jdW1lbnQ6eG1sbnM6Y29udGFpbmVyIj4KICA8cm9vdGZpbGVzPgogICAgPHJvb3RmaWxlIGZ1bGwtcGF0aD0iT0VCUFMvY29udGVudC5vcGYiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL29lYnBzLXBhY2thZ2UreG1sIi8+CiAgPC9yb290ZmlsZXM+CjwvY29udGFpbmVyPgpQSwMECgAAAAAAFWC1XAAAAAAAAAAAAAAAAAYAHABPRUJQUy9VVAkAA5KmDmqSpg5qdXgLAAEE9QEAAAQUAAAAUEsDBAoAAAAAABVgtVz+j0KUBQEAAAUBAAAUABwAT0VCUFMvY2hhcHRlcjEueGh0bWxVVAkAA5KmDmqSpg5qdXgLAAEE9QEAAAQUAAAAPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPGh0bWwgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGh0bWwiPgo8aGVhZD48dGl0bGU+Q2hhcHRlciAxPC90aXRsZT48L2hlYWQ+Cjxib2R5PgogIDxoMT5DaGFwdGVyIE9uZTwvaDE+CiAgPHA+VGhpcyBpcyBwYXJhZ3JhcGggb25lIG9mIGNoYXB0ZXIgb25lLjwvcD4KICA8cD5UaGlzIGlzIHBhcmFncmFwaCB0d28gb2YgY2hhcHRlciBvbmUuPC9wPgo8L2JvZHk+CjwvaHRtbD4KUEsDBAoAAAAAABVgtVxg0/7L1gAAANYAAAAUABwAT0VCUFMvY2hhcHRlcjIueGh0bWxVVAkAA5KmDmqSpg5qdXgLAAEE9QEAAAQUAAAAPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPGh0bWwgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGh0bWwiPgo8aGVhZD48dGl0bGU+Q2hhcHRlciAyPC90aXRsZT48L2hlYWQ+Cjxib2R5PgogIDxoMT5DaGFwdGVyIFR3bzwvaDE+CiAgPHA+VGhpcyBpcyBwYXJhZ3JhcGggb25lIG9mIGNoYXB0ZXIgdHdvLjwvcD4KPC9ib2R5Pgo8L2h0bWw+ClBLAwQKAAAAAAAVYLVcnEcFcUECAABBAgAAEQAcAE9FQlBTL2NvbnRlbnQub3BmVVQJAAOSpg5qkqYOanV4CwABBPUBAAAEFAAAADw/eG1sIHZlcnNpb249IjEuMCIgZW5jb2Rpbmc9IlVURi04Ij8+CjxwYWNrYWdlIHhtbG5zPSJodHRwOi8vd3d3LmlkcGYub3JnLzIwMDcvb3BmIiB1bmlxdWUtaWRlbnRpZmllcj0iYm9va2lkIiB2ZXJzaW9uPSIzLjAiPgogIDxtZXRhZGF0YSB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iPgogICAgPGRjOnRpdGxlPlRlc3QgQm9vazwvZGM6dGl0bGU+CiAgICA8ZGM6Y3JlYXRvcj5UZXN0IEF1dGhvcjwvZGM6Y3JlYXRvcj4KICAgIDxkYzpsYW5ndWFnZT5lbjwvZGM6bGFuZ3VhZ2U+CiAgPC9tZXRhZGF0YT4KICA8bWFuaWZlc3Q+CiAgICA8aXRlbSBpZD0iY2gxIiBocmVmPSJjaGFwdGVyMS54aHRtbCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veGh0bWwreG1sIi8+CiAgICA8aXRlbSBpZD0iY2gyIiBocmVmPSJjaGFwdGVyMi54aHRtbCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veGh0bWwreG1sIi8+CiAgPC9tYW5pZmVzdD4KICA8c3BpbmU+CiAgICA8aXRlbXJlZiBpZHJlZj0iY2gxIi8+CiAgICA8aXRlbXJlZiBpZHJlZj0iY2gyIi8+CiAgPC9zcGluZT4KPC9wYWNrYWdlPgpQSwECHgMKAAAAAAAVYLVcb2GrLBQAAAAUAAAACAAYAAAAAAAAAAAApIEAAAAAbWltZXR5cGVVVAUAA5KmDmp1eAsAAQT1AQAABBQAAABQSwECHgMKAAAAAAAVYLVcAAAAAAAAAAAAAAAACQAYAAAAAAAAABAA7UFWAAAATUVUQS1JTkYvVVQFAAOSpg5qdXgLAAEE9QEAAAQUAAAAUEsBAh4DCgAAAAAAFWC1XBa1s9z8AAAA/AAAABYAGAAAAAAAAAAAAKSBmQAAAE1FVEEtSU5GL2NvbnRhaW5lci54bWxVVAUAA5KmDmp1eAsAAQT1AQAABBQAAABQSwECHgMKAAAAAAAVYLVcAAAAAAAAAAAAAAAABgAYAAAAAAAAABAA7UHlAQAAT0VCUFMvVVQFAAOSpg5qdXgLAAEE9QEAAAQUAAAAUEsBAh4DCgAAAAAAFWC1XP6PQpQFAQAABQEAABQAGAAAAAAAAAAAAKSBJQIAAE9FQlBTL2NoYXB0ZXIxLnhodG1sVVQFAAOSpg5qdXgLAAEE9QEAAAQUAAAAUEsBAh4DCgAAAAAAFWC1XGDT/svWAAAA1gAAABQAGAAAAAAAAAAAAKSBeAMAAE9FQlBTL2NoYXB0ZXIyLnhodG1sVVQFAAOSpg5qdXgLAAEE9QEAAAQUAAAAUEsBAh4DCgAAAAAAFWC1XJxHBXFBAgAAQQIAABEAGAAAAAAAAAAAAKSBnAQAAE9FQlBTL2NvbnRlbnQub3BmVVQFAAOSpg5qdXgLAAEE9QEAAAQUAAAAUEsFBgAAAAAHAAcAUAIAACgHAAAAAA=="
        
        guard let epubData = Data(base64Encoded: base64Epub) else {
            XCTFail("Failed to decode base64 EPUB")
            return
        }
        
        let epubURL = tempDirURL.appendingPathComponent("test_book.epub")
        try epubData.write(to: epubURL)
        
        let parsed = try EpubTextParser.parse(epubURL: epubURL)
        
        XCTAssertEqual(parsed.title, "Test Book")
        XCTAssertEqual(parsed.author, "Test Author")
        XCTAssertEqual(parsed.slug, "test_book")
        XCTAssertEqual(parsed.chapters.count, 2)
        
        // Check Chapter 1 Content
        let ch1 = parsed.chapters[0]
        XCTAssertEqual(ch1.title, "Chapter 1") // Standard default titling
        XCTAssertEqual(ch1.paragraphs.count, 2)
        XCTAssertEqual(ch1.paragraphs[0].text, "This is paragraph one of chapter one.")
        XCTAssertEqual(ch1.paragraphs[1].text, "This is paragraph two of chapter one.")
        
        // Check Chapter 2 Content
        let ch2 = parsed.chapters[1]
        XCTAssertEqual(ch2.title, "Chapter 2")
        XCTAssertEqual(ch2.paragraphs.count, 1)
        XCTAssertEqual(ch2.paragraphs[0].text, "This is paragraph one of chapter two.")
    }

    func testParseInvalidEpubMissingContainer() {
        // Zip file missing META-INF/container.xml
        let malformedEpubBase64 = "UEsDBAoAAAAAAEdgtVxvYassFAAAABQAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi9lcHViK3ppcFBLAQIeAwoAAAAAAEdgtVxvYassFAAAABQAAAAIAAAAAAAAAAAAAACkgQAAAABtaW1ldHlwZVBLBQYAAAAAAQABADYAAAA6AAAAAAA="
        
        guard let epubData = Data(base64Encoded: malformedEpubBase64) else {
            XCTFail("Failed to decode base64")
            return
        }
        let epubURL = tempDirURL.appendingPathComponent("invalid.epub")
        try? epubData.write(to: epubURL)
        
        XCTAssertThrowsError(try EpubTextParser.parse(epubURL: epubURL)) { error in
            XCTAssertEqual(error as? EpubTextParserError, EpubTextParserError.missingContainer)
        }
    }
}
