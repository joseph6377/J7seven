import Foundation
import UIKit
import SwiftSoup

struct WebChapter {
    let title: String
    let paragraphs: [Paragraph]
}

struct WebArticleToParsedBook {
    
    struct ParsedBook {
        let title: String
        let author: String?
        let slug: String
        let coverData: Data?
        let chapters: [WebChapter]
        let sourceURL: URL
    }
    
    static func map(
        html: String,
        url: URL,
        jsonLd: JsonLdArticle?,
        readability: ReadabilityResult?,
        normalizedText: String
    ) async -> ParsedBook {
        let doc = (try? SwiftSoup.parse(html)) ?? Document("")
        
        // 1. Resolve Title
        var title = "Untitled Web Article"
        if let jsonTitle = jsonLd?.headline, !jsonTitle.isEmpty {
            title = jsonTitle
        } else if let readTitle = readability?.title, !readTitle.isEmpty {
            title = readTitle
        } else if let h1 = try? doc.select("h1").first()?.text(), !h1.isEmpty {
            title = h1
        } else if let t = try? doc.title(), !t.isEmpty {
            title = t
        }
        
        // 2. Resolve Author
        var author: String? = nil
        if let jsonAuthor = jsonLd?.authorName, !jsonAuthor.isEmpty {
            author = jsonAuthor
        } else if let readAuthor = readability?.byline, !readAuthor.isEmpty {
            author = readAuthor
        } else if let metaAuthor = try? doc.select("meta[name=author]").attr("content"), !metaAuthor.isEmpty {
            author = metaAuthor
        } else if let relAuthor = try? doc.select("[rel=author]").first()?.text(), !relAuthor.isEmpty {
            author = relAuthor
        }
        if author == nil || author?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            author = "Unknown Author"
        }
        
        // 3. Resolve and Download Cover Image
        var coverData: Data? = nil
        var coverUrlString: String? = nil
        
        if let jsonImg = jsonLd?.imageUrl, !jsonImg.isEmpty {
            coverUrlString = jsonImg
        } else if let ogImg = try? doc.select("meta[property=og:image]").attr("content"), !ogImg.isEmpty {
            coverUrlString = ogImg
        } else if let firstFigImg = try? doc.select("figure img, article img").first()?.attr("src"), !firstFigImg.isEmpty {
            coverUrlString = firstFigImg
        }
        
        if let urlString = coverUrlString,
           let absoluteURL = URL(string: urlString, relativeTo: url) {
            let finalURL = absoluteURL.absoluteURL
            print("[WebArticleMapper] Downloading cover image from: \(finalURL.absoluteString)")
            coverData = await downloadAndResizeImage(from: finalURL)
        }
        
        // 4. Split Normalized Text into Paragraphs
        let paragraphTexts = normalizedText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var paragraphs = paragraphTexts.map { Paragraph(text: $0, pageNumber: nil) }
        
        // Prepend the article title as the first paragraph so it is styled as a header in the UI and read first by the TTS engine
        if !title.isEmpty {
            let alreadyHasTitle = paragraphs.first?.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            if !alreadyHasTitle {
                paragraphs.insert(Paragraph(text: title, pageNumber: nil), at: 0)
            }
        }
        
        let oneChapter = WebChapter(
            title: title,
            paragraphs: paragraphs
        )
        
        let slug = url.deletingPathExtension().lastPathComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        
        let cleanSlug = slug.isEmpty ? UUID().uuidString.prefix(8).lowercased() : slug
        
        return ParsedBook(
            title: title,
            author: author,
            slug: String(cleanSlug),
            coverData: coverData,
            chapters: [oneChapter],
            sourceURL: url
        )
    }
    
    // MARK: - Image Downloader & Resizer
    
    private static func downloadAndResizeImage(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        request.setValue(HtmlFetcher.safariUserAgent, forHTTPHeaderField: "User-Agent")
        
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = UIImage(data: data) else {
            print("[WebArticleMapper] Failed to download or parse cover image.")
            return nil
        }
        
        // Target 2:3 ratio standard book cover (e.g. 300x450) — aspect-fill crop, not stretch
        let targetSize = CGSize(width: 300, height: 450)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { ctx in
            let sourceSize = image.size
            let scale = max(targetSize.width / sourceSize.width,
                            targetSize.height / sourceSize.height)
            let drawSize = CGSize(width: sourceSize.width * scale,
                                  height: sourceSize.height * scale)
            let drawOrigin = CGPoint(x: (targetSize.width - drawSize.width) / 2,
                                     y: (targetSize.height - drawSize.height) / 2)
            ctx.cgContext.clip(to: CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
        
        var compression: CGFloat = 0.8
        var imageData = resizedImage.jpegData(compressionQuality: compression)
        while let data = imageData, data.count > 200 * 1024 && compression > 0.1 {
            compression -= 0.1
            imageData = resizedImage.jpegData(compressionQuality: compression)
        }
        
        print("[WebArticleMapper] Image compressed successfully. Size: \(Double(imageData?.count ?? 0) / 1024.0) KB")
        return imageData
    }
}
