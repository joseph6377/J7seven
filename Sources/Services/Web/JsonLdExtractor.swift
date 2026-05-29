import Foundation
import SwiftSoup

struct JsonLdArticle {
    let headline: String
    let articleBody: String
    let authorName: String?
    let datePublished: String?
    let dateModified: String?
    let imageUrl: String?
}

struct JsonLdExtractor {
    
    static func extract(html: String) -> JsonLdArticle? {
        do {
            let doc = try SwiftSoup.parse(html)
            let scripts = try doc.select("script[type=application/ld+json]")
            for script in scripts {
                let jsonText = script.data()
                guard !jsonText.isEmpty else { continue }
                
                guard let data = jsonText.data(using: .utf8),
                      let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                      let article = findArticle(in: jsonObject)
                else { continue }
                
                return article
            }
        } catch {
            print("[JSON-LD] Error: \(error)")
        }
        return nil
    }
    
    static func extract(fromBlocks jsonBlocks: [String]) -> JsonLdArticle? {
        for jsonText in jsonBlocks {
            let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            guard let data = trimmed.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                  let article = findArticle(in: jsonObject)
            else { continue }
            
            return article
        }
        return nil
    }
    
    private static func findArticle(in jsonObject: Any) -> JsonLdArticle? {
        if let dict = jsonObject as? [String: Any] {
            if let type = dict["@type"] as? String,
               ["Article", "NewsArticle", "BlogPosting", "TechArticle", "Report"].contains(type),
               let articleBody = dict["articleBody"] as? String,
               articleBody.count > 200 {
                
                let headline = (dict["headline"] as? String) ?? (dict["name"] as? String) ?? "Untitled"
                let authorName = parseAuthor(dict["author"])
                let datePublished = dict["datePublished"] as? String
                let dateModified = dict["dateModified"] as? String
                let imageUrl = parseImage(dict["image"])
                
                return JsonLdArticle(
                    headline: headline,
                    articleBody: articleBody,
                    authorName: authorName,
                    datePublished: datePublished,
                    dateModified: dateModified,
                    imageUrl: imageUrl
                )
            }
            
            // Walk @graph array if present
            if let graph = dict["@graph"] as? [Any] {
                for item in graph {
                    if let article = findArticle(in: item) {
                        return article
                    }
                }
            }
            
            // Recursively search child dictionaries
            for (_, value) in dict {
                if let childArticle = findArticle(in: value) {
                    return childArticle
                }
            }
        } else if let array = jsonObject as? [Any] {
            for item in array {
                if let article = findArticle(in: item) {
                    return article
                }
            }
        }
        return nil
    }
    
    private static func parseAuthor(_ authorObj: Any?) -> String? {
        guard let authorObj = authorObj else { return nil }
        if let authorDict = authorObj as? [String: Any] {
            return authorDict["name"] as? String
        }
        if let authorDict = authorObj as? NSDictionary {
            return authorDict["name"] as? String
        }
        if let authorString = authorObj as? String {
            return authorString
        }
        if let authorArray = authorObj as? [Any], let first = authorArray.first {
            if let firstDict = first as? [String: Any] {
                return firstDict["name"] as? String
            }
            if let firstDict = first as? NSDictionary {
                return firstDict["name"] as? String
            }
        }
        return nil
    }
    
    private static func parseImage(_ imageObj: Any?) -> String? {
        guard let imageObj = imageObj else { return nil }
        if let imageString = imageObj as? String {
            return imageString
        }
        if let imageDict = imageObj as? [String: Any] {
            return imageDict["url"] as? String
        }
        if let imageDict = imageObj as? NSDictionary {
            return imageDict["url"] as? String
        }
        if let imageArray = imageObj as? [String], let first = imageArray.first {
            return first
        }
        if let imageArray = imageObj as? NSArray, let first = imageArray.firstObject as? String {
            return first
        }
        if let imageArray = imageObj as? [Any], let first = imageArray.first {
            if let firstString = first as? String {
                return firstString
            }
            if let firstDict = first as? [String: Any] {
                return firstDict["url"] as? String
            }
            if let firstDict = first as? NSDictionary {
                return firstDict["url"] as? String
            }
        }
        return nil
    }
}
