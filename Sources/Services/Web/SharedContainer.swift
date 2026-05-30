import Foundation

public enum SharedContainer {
    public static let appGroup = "group.in.josepht.booksappv2"
    
    public static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)!
            .appendingPathComponent("share-inbox", isDirectory: true)
    }
    
    public static func write(_ payload: SharedPayload, id: String) throws {
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        let url = containerURL.appendingPathComponent("\(id).json")
        try JSONEncoder().encode(payload).write(to: url, options: .atomic)
    }
    
    public static func read(id: String) throws -> SharedPayload {
        let url = containerURL.appendingPathComponent("\(id).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SharedPayload.self, from: data)
    }
    
    public static func delete(id: String) {
        let url = containerURL.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: url)
    }
}

public struct SharedPayload: Codable, Sendable, Identifiable {
    public var id: String { url.absoluteString }
    
    public let url: URL
    public let title: String?
    public let renderedHtml: String?  // Pre-rendered DOM from Safari
    public let jsonLd: [String]?       // Pre-extracted JSON-LD blocks
    
    public init(url: URL, title: String?, renderedHtml: String?, jsonLd: [String]?) {
        self.url = url
        self.title = title
        self.renderedHtml = renderedHtml
        self.jsonLd = jsonLd
    }
}
