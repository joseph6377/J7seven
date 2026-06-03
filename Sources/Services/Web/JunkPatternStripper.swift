import Foundation
import SwiftSoup

struct JunkPatternStripper {
    
    static func strip(html: String, keepCodeBlocks: Bool) throws -> String {
        let doc = try SwiftSoup.parse(html)
        
        // Pass 1: Cookie/consent banners
        try stripCookies(doc)
        
        // Pass 2: Newsletter signup forms
        try stripNewsletters(doc)
        
        // Pass 3: Related-article rails
        try stripRelatedRails(doc)
        
        // Pass 4: Author bio blocks
        try stripAuthorBios(doc)
        
        // Pass 5: Comments
        try stripComments(doc)
        
        // Pass 6: Social share rows
        try stripSocialShares(doc)
        
        // Pass 7: Breadcrumbs
        try stripBreadcrumbs(doc)
        
        // Pass 8: Reading time widgets
        try stripReadingTimes(doc)
        
        // Pass 9: Pull quotes
        try stripPullQuotes(doc)
        
        // Pass 10: Inline ads
        try stripAds(doc)
        
        // Pass 11: Timestamps keeping & normalizations
        try normalizeTimestamps(doc)
        
        // Pass 12: Image captions wrapping
        try normalizeImageCaptions(doc)
        
        // Pass 13: Footnote merging and anchor removal
        try processFootnotes(doc)
        
        // Pass 14: Code block replacements
        try processCodeBlocks(doc, keepCodeBlocks: keepCodeBlocks)
        
        // Pass 15: Math ML and alternative text conversion
        try processMath(doc)
        
        return try doc.outerHtml()
    }
    
    // MARK: - Filter Passes
    
    private static func stripCookies(_ doc: Document) throws {
        let keywords = ["consent", "cookies", "privacy choices", "akzeptieren", "acepto", "accept all", "cookie banner"]
        let elements = try doc.body()?.getAllElements() ?? Elements()
        var toRemove = [Element]()
        
        for el in elements {
            if el.tagName() == "body" || el.tagName() == "html" {
                continue
            }
            let style = (try? el.attr("style"))?.lowercased() ?? ""
            let isFixedOrZIndex = style.contains("position: fixed") || style.contains("position:fixed") || style.contains("z-index")
            
            let text = el.ownText().lowercased()
            let id = el.id()
            let className = (try? el.className())?.lowercased() ?? ""
            
            var matchesKeyword = false
            for kw in keywords {
                if text.contains(kw) || id.contains(kw) || className.contains(kw) {
                    matchesKeyword = true
                    break
                }
            }
            
            if isFixedOrZIndex && matchesKeyword {
                toRemove.append(el)
            }
        }
        
        for el in toRemove {
            try? el.remove()
        }
    }
    
    private static func stripNewsletters(_ doc: Document) throws {
        let forms = try doc.select("form")
        var toRemove = [Element]()
        
        for form in forms {
            let emailInputs = try form.select("input[type=\"email\"], input[name*=\"email\"]")
            if !emailInputs.isEmpty {
                let formText = try form.text()
                let regex = try NSRegularExpression(pattern: "subscribe|newsletter|sign up|join", options: .caseInsensitive)
                let range = NSRange(location: 0, length: formText.utf16.count)
                if regex.firstMatch(in: formText, options: [], range: range) != nil {
                    toRemove.append(form)
                }
            }
        }
        
        for form in toRemove {
            try? form.remove()
        }
    }
    
    private static func stripRelatedRails(_ doc: Document) throws {
        let elements = try doc.body()?.getAllElements() ?? Elements()
        let regex = try NSRegularExpression(pattern: "related|more|recommended|more-from|you-may-also|trending", options: .caseInsensitive)
        var toRemove = [Element]()
        
        for el in elements {
            if el.tagName() == "body" || el.tagName() == "html" || el.tagName() == "article" || el.tagName() == "main" {
                continue
            }
            let ariaLabel = (try? el.attr("aria-label")) ?? ""
            let className = (try? el.className()) ?? ""
            let id = el.id()
            
            let matchAria = !ariaLabel.isEmpty && regex.firstMatch(in: ariaLabel, options: [], range: NSRange(location: 0, length: ariaLabel.utf16.count)) != nil
            let matchClass = !className.isEmpty && regex.firstMatch(in: className, options: [], range: NSRange(location: 0, length: className.utf16.count)) != nil
            let matchId = !id.isEmpty && regex.firstMatch(in: id, options: [], range: NSRange(location: 0, length: id.utf16.count)) != nil
            
            if matchAria || matchClass || matchId {
                toRemove.append(el)
            }
        }
        
        for el in toRemove {
            try? el.remove()
        }
    }
    
    private static func stripAuthorBios(_ doc: Document) throws {
        let articles = try doc.select("article")
        var toRemove = [Element]()
        
        for article in articles {
            let asides = try article.parent()?.select("aside") ?? Elements()
            for aside in asides {
                let headings = try aside.select("h1, h2, h3, h4, h5, h6")
                for heading in headings {
                    let text = try heading.text().lowercased()
                    if text.contains("about the author") {
                        toRemove.append(aside)
                        break
                    }
                }
            }
        }
        
        let headings = try doc.select("h1, h2, h3, h4, h5, h6")
        for heading in headings {
            let text = try heading.text().lowercased()
            if text.contains("about the author") {
                if let parent = heading.parent(),
                   parent.tagName() != "body",
                   parent.tagName() != "html",
                   parent.tagName() != "article",
                   parent.tagName() != "main" {
                    toRemove.append(parent)
                }
            }
        }
        
        for el in toRemove {
            try? el.remove()
        }
    }
    
    private static func stripComments(_ doc: Document) throws {
        let elements = try doc.select("#disqus_thread, [role=\"comments\"], [class*=\"comments\"], section[class*=\"comments\"]")
        for el in elements {
            if el.tagName() != "body" && el.tagName() != "html" {
                try? el.remove()
            }
        }
    }
    
    private static func stripSocialShares(_ doc: Document) throws {
        let elements = try doc.body()?.getAllElements() ?? Elements()
        var toRemove = [Element]()
        
        for el in elements {
            if el.tagName() == "body" || el.tagName() == "html" {
                continue
            }
            let links = try el.select("a[href]")
            var socialLinkCount = 0
            for link in links {
                let href = (try? link.attr("href"))?.lowercased() ?? ""
                if href.contains("twitter.com") || href.contains("x.com") || href.contains("facebook.com") || href.contains("linkedin.com") || href.contains("reddit.com") || href.contains("threads.net") {
                    socialLinkCount += 1
                }
            }
            if socialLinkCount >= 3 {
                // Verify no child element of el also has >= 3 social links.
                // This ensures we only remove the innermost container of social links.
                var childHasThree = false
                for child in el.children() {
                    var childSocialCount = 0
                    for childLink in try child.select("a[href]") {
                        let href = (try? childLink.attr("href"))?.lowercased() ?? ""
                        if href.contains("twitter.com") || href.contains("x.com") || href.contains("facebook.com") || href.contains("linkedin.com") || href.contains("reddit.com") || href.contains("threads.net") {
                            childSocialCount += 1
                        }
                    }
                    if childSocialCount >= 3 {
                        childHasThree = true
                        break
                    }
                }
                if !childHasThree {
                    toRemove.append(el)
                }
            }
        }
        
        for el in toRemove {
            try? el.remove()
        }
    }
    
    private static func stripBreadcrumbs(_ doc: Document) throws {
        let elements = try doc.select("nav[aria-label*=\"breadcrumb\"], [itemtype*=\"BreadcrumbList\"], [class*=\"breadcrumb\"]")
        for el in elements {
            if el.tagName() != "body" && el.tagName() != "html" {
                try? el.remove()
            }
        }
    }
    
    private static func stripReadingTimes(_ doc: Document) throws {
        let elements = try doc.body()?.getAllElements() ?? Elements()
        let regex = try NSRegularExpression(pattern: "\\b\\d+\\s*min(ute)?s?\\s*read\\b", options: .caseInsensitive)
        var toRemove = [Element]()
        
        for el in elements {
            if el.tagName() == "body" || el.tagName() == "html" || el.tagName() == "article" || el.tagName() == "main" {
                continue
            }
            let text = try el.text()
            if text.count < 100 && regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil {
                toRemove.append(el)
            }
        }
        
        for el in toRemove {
            try? el.remove()
        }
    }
    
    private static func stripPullQuotes(_ doc: Document) throws {
        let elements = try doc.select("blockquote[class*=\"pullquote\"], aside[class*=\"pullquote\"]")
        for el in elements {
            if el.tagName() != "body" && el.tagName() != "html" {
                try? el.remove()
            }
        }
    }
    
    private static func stripAds(_ doc: Document) throws {
        let elements = try doc.select("[class*=\"ad-\"], [id*=\"-ad-\"], [data-ad], iframe")
        for el in elements {
            if el.tagName() != "body" && el.tagName() != "html" {
                try? el.remove()
            }
        }
    }
    
    private static func normalizeTimestamps(_ doc: Document) throws {
        // Handled in Stage 5 Date Normalizer
    }
    
    private static func normalizeImageCaptions(_ doc: Document) throws {
        let figcaptions = try doc.select("figcaption")
        for fig in figcaptions {
            let text = try fig.text()
            let p = try doc.createElement("p")
            try p.attr("data-tts-prefix", "Image caption: ")
            try p.text(text)
            try fig.replaceWith(p)
        }
    }
    
    private static func processFootnotes(_ doc: Document) throws {
        let footnoteContainers = try doc.select("aside[class*=\"footnote\"], [role=\"doc-endnote\"], [class*=\"footnote-content\"], [id*=\"footnote\"]")
        var footnotesById = [String: String]()
        for container in footnoteContainers {
            let id = container.id()
            if !id.isEmpty {
                footnotesById[id] = (try? container.text()) ?? ""
                try? container.remove()
            }
        }
        
        let supLinks = try doc.select("sup, a[href*=\"#fn\"], a[class*=\"footnote\"]")
        
        for link in supLinks {
            let href = (try? link.attr("href")) ?? ""
            var id = href.hasPrefix("#") ? String(href.dropFirst()) : href
            
            // Fallback: If id is empty, parse digits inside superscript text
            if id.isEmpty {
                let cleanText = (try? link.text())?.trimmingCharacters(in: CharacterSet.decimalDigits.inverted) ?? ""
                if !cleanText.isEmpty {
                    id = cleanText
                }
            }
            
            if let fnText = footnotesById[id], !fnText.isEmpty {
                var parent = link.parent()
                while parent != nil && parent?.tagName() != "p" {
                    parent = parent?.parent()
                }
                
                if let p = parent {
                    try p.appendText(" Footnote: " + fnText)
                }
            }
            try? link.remove()
        }
    }
    
    private static func processCodeBlocks(_ doc: Document, keepCodeBlocks: Bool) throws {
        let codeElements = try doc.select("pre, code")
        for code in codeElements {
            if keepCodeBlocks {
                // keep the original text
            } else {
                let replacement = try doc.createElement("span")
                try replacement.text("[code block]")
                try code.replaceWith(replacement)
            }
        }
    }
    
    private static func processMath(_ doc: Document) throws {
        let mathElements = try doc.select("math, .MathJax, .katex")
        for math in mathElements {
            let altText = (try? math.attr("alttext")) ?? ""
            if !altText.isEmpty {
                let replacement = try doc.createElement("span")
                try replacement.text(altText)
                try math.replaceWith(replacement)
            } else {
                try? math.remove()
            }
        }
    }
}

extension Element {
    // helper to extract prefix if present
    func ttsPrefix() -> String {
        return (try? attr("data-tts-prefix")) ?? ""
    }
}
