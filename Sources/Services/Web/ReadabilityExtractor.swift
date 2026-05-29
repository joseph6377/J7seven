import Foundation
import SwiftReadability

struct ReadabilityResult {
    let html: String
    let title: String
    let byline: String?
    let excerpt: String?
}

struct ReadabilityExtractor {
    
    static func extract(html: String, url: URL) async throws -> ReadabilityResult {
        var options = ReadabilityOptions()
        options.keepClasses = true
        options.classesToPreserve = ["figure", "figcaption", "footnote", "cite"]
        options.charThreshold = 500
        
        let reader = Readability(html: html, url: url, options: options)
        guard let parsed = try reader.parse() else {
            throw URLError(.cannotParseResponse)
        }
        
        return ReadabilityResult(
            html: parsed.content ?? "",
            title: parsed.title ?? "",
            byline: parsed.byline,
            excerpt: parsed.excerpt
        )
    }
}
