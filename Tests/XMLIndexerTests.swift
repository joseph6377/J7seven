import XCTest
@testable import BooksAppV2

final class XMLIndexerTests: XCTestCase {

    func testBasicXMLParsingAndText() {
        let xmlString = "<root><title>Hello World</title></root>"
        let data = xmlString.data(using: .utf8)!
        let indexer = XMLIndexer(data: data)
        
        XCTAssertEqual(indexer.name, "#document")
        
        let root = indexer.child("root")
        XCTAssertNotNil(root)
        XCTAssertEqual(root?.name, "root")
        
        let title = root?.child("title")
        XCTAssertNotNil(title)
        XCTAssertEqual(title?.name, "title")
        XCTAssertEqual(title?.text, "Hello World")
    }

    func testChildrenNamed() {
        let xmlString = "<root><item>One</item><item>Two</item><other>Three</other></root>"
        let data = xmlString.data(using: .utf8)!
        let indexer = XMLIndexer(data: data)
        
        let root = indexer.child("root")
        XCTAssertNotNil(root)
        
        let items = root?.children(named: "item")
        XCTAssertEqual(items?.count, 2)
        XCTAssertEqual(items?[0].text, "One")
        XCTAssertEqual(items?[1].text, "Two")
    }

    func testAttributeParsing() {
        let xmlString = "<root id=\"123\" type=\"test\"><child name=\"my-child\"/></root>"
        let data = xmlString.data(using: .utf8)!
        let indexer = XMLIndexer(data: data)
        
        let root = indexer.child("root")
        XCTAssertNotNil(root)
        XCTAssertEqual(root?.attributes["id"], "123")
        XCTAssertEqual(root?.attributes["type"], "test")
        
        let child = root?.child("child")
        XCTAssertNotNil(child)
        XCTAssertEqual(child?.attributes["name"], "my-child")
    }

    func testNamespaceStripping() {
        let xmlString = "<root xmlns:opf=\"http://www.idpf.org/2007/opf\"><opf:metadata>Metadata Content</opf:metadata></root>"
        let data = xmlString.data(using: .utf8)!
        let indexer = XMLIndexer(data: data)
        
        let root = indexer.child("root")
        XCTAssertNotNil(root)
        
        // XMLIndexer should successfully strip namespace prefix "opf" and match local name "metadata"
        let metadata = root?.child("metadata")
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.text, "Metadata Content")
    }

    func testEntitySanitization() {
        // XMLParser defaults to choking on undefined HTML entities. XMLIndexer sanitizes these.
        let xmlString = "<p>Here is some &ldquo;quoted&rdquo; text with a non-breaking space&nbsp;and an emdash&mdash;.</p>"
        let data = xmlString.data(using: .utf8)!
        let indexer = XMLIndexer(data: data)
        
        let pNode = indexer.child("p")
        XCTAssertNotNil(pNode)
        
        let text = pNode?.text ?? ""
        XCTAssertTrue(text.contains("\u{201C}quoted\u{201D}")) // &ldquo; / &rdquo;
        XCTAssertTrue(text.contains("\u{00A0}"))             // &nbsp;
        XCTAssertTrue(text.contains("\u{2014}"))             // &mdash;
    }
    
    func testAllDescendants() {
        let xmlString = "<root><a><b><c>Nested</c></b></a></root>"
        let data = xmlString.data(using: .utf8)!
        let indexer = XMLIndexer(data: data)
        
        let descendants = indexer.allDescendants
        let names = descendants.map { $0.name }
        
        XCTAssertTrue(names.contains("root"))
        XCTAssertTrue(names.contains("a"))
        XCTAssertTrue(names.contains("b"))
        XCTAssertTrue(names.contains("c"))
    }
}
