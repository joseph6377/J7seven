import Foundation
import SwiftSoup

struct TtsTextNormalizer {
    
    static let commonInitialisms: Set<String> = [
        "FBI", "CIA", "LLM", "NSA", "HTML", "CSS", "XML", "PDF", "USA", "URL", "UI", "UX", "API", "CPU", "GPU", "RAM", "ROM", "USB",
        "SMS", "GPS", "DIY", "KFC", "BMW", "CNN", "BBC", "NBC", "CBS", "ABC", "HBO", "MTV", "SQL", "DNS", "IP", "ISP", "LAN", "WAN",
        "VPN", "FTP", "SSH", "HTTP", "HTTPS", "SSL", "TLS", "SDK", "IDE", "CLI", "GUI", "JSON", "CSV", "SVG", "PNG", "JPG", "JPEG",
        "GIF", "MP3", "MP4", "AVI", "MKV", "PDF", "PPT", "DOC", "XLS", "EOF", "LOF", "DIY", "TBA", "TBD", "ETA", "ETD", "FAQ", "FYI",
        "AKA", "ASAP", "DIY", "VIP", "CEO", "CFO", "CTO", "COO", "CMO", "CIO", "HR", "PR", "R&D", "QA", "QC", "PM", "AM", "PM", "BC",
        "AD", "BCE", "CE", "GMT", "EST", "PST", "CST", "MST", "UTC", "IQ", "EQ", "AI", "ML", "DL", "NLP", "CV", "AGI", "ASI", "NPC",
        "RPG", "FPS", "RTS", "MMO", "PvP", "PvE", "DLC", "XP", "HP", "MP", "AFK", "BRB", "GTG", "LOL", "BRB", "OMG", "IMO", "IMHO",
        "TBH", "TL;DR", "TOS", "EULA", "NDA", "SOP", "KPI", "ROI", "B2B", "B2C", "SaaS", "PaaS", "IaaS", "AWS", "GCP", "IBM", "AMD",
        "Intel", "NVIDIA", "ARM", "iOS", "OS", "macOS", "GNU", "MIT", "BSD", "GPL", "JSON", "YAML", "REST", "SOAP", "RPC", "gRPC",
        "JWT", "OAuth", "SAML", "SSO", "MFA", "2FA", "OTP", "CSRF", "XSS", "SQLi", "DDoS", "CDN", "DNS", "DHCP", "NAT", "CIDR", "VPC",
        "EC2", "S3", "RDS", "DynamoDB", "Lambda", "Docker", "K8s", "CI", "CD", "Git", "SVN", "CVS", "P2P", "Tor", "IPFS", "BTC", "ETH",
        "NFT", "DeFi", "DAO", "Web3", "VR", "AR", "MR", "XR", "IoT", "RFID", "NFC", "BLE", "LTE", "5G", "4G", "3G", "GSM", "CDMA",
        "SIM", "eSIM", "PIN", "PUK", "IMEI", "IMSI", "MAC", "IP", "CIDR", "Subnet", "Gateway", "Router", "Switch", "Hub", "Modem"
    ]
    
    static func normalize(text: String) -> String {
        var result = text
        
        // 1. Normalize URLs
        result = normalizeURLs(result)
        
        // 2. Abbreviation lexicon (bundled + user extensible)
        let bundleLexicon = loadBundledLexicon()
        result = normalizeAbbreviations(result, bundleLexicon: bundleLexicon)
        
        // 3. Acronym/Initialism spelling
        result = formatInitialisms(result)
        
        // 4. Currency and numbers
        result = normalizeCurrencies(result)
        result = normalizeDates(result)
        
        // 5. Markdown leftovers
        result = stripMarkdown(result)
        
        return result
    }
    
    // MARK: - Normalization Helpers
    
    static func normalizeURLs(_ text: String) -> String {
        var result = text
        
        // Inside parens: strip entirely
        let parenPattern = "\\(\\s*https?://[^\\s)]+\\s*\\)"
        if let regex = try? NSRegularExpression(pattern: parenPattern) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                result = (result as NSString).replacingCharacters(in: match.range, with: "")
            }
        }
        
        // Standalone URL: link to {host}
        let urlPattern = "https?://(\\S+)"
        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                let fullUrlString = nsString.substring(with: match.range)
                if let url = URL(string: fullUrlString), let host = url.host {
                    let replaced = "link to \(host)"
                    result = (result as NSString).replacingCharacters(in: match.range, with: replaced)
                } else {
                    result = (result as NSString).replacingCharacters(in: match.range, with: "")
                }
            }
        }
        return result
    }
    
    static func loadBundledLexicon() -> [String: String] {
        guard let path = Bundle.main.path(forResource: "tts-abbreviations", ofType: "yaml"),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }
        
        var dict = [String: String]()
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let val = parts[1].trimmingCharacters(in: .whitespaces)
                dict[key] = val
            }
        }
        return dict
    }
    
    static func getUserAbbreviations() -> [String: String] {
        return UserDefaults.standard.dictionary(forKey: "web.userAbbreviations") as? [String: String] ?? [:]
    }
    
    static func normalizeAbbreviations(_ text: String, bundleLexicon: [String: String]) -> String {
        var result = text
        let userLexicon = getUserAbbreviations()
        let lexicon = bundleLexicon.merging(userLexicon) { (_, new) in new }
        
        for (abbr, replacement) in lexicon {
            let escapedAbbr = NSRegularExpression.escapedPattern(for: abbr)
            // Match word boundaries: handle space or start/end of line, or standard punctuation
            let pattern = "(?<=^|\\s)\(escapedAbbr)(?=$|\\s|\\p{Punct})"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsString = result as NSString
                let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
                for match in matches.reversed() {
                    result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }
        
        return result
    }
    
    static func formatInitialisms(_ text: String) -> String {
        let pattern = "\\b([A-Z]{2,})\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        
        var result = text
        for match in matches.reversed() {
            let word = nsString.substring(with: match.range)
            if commonInitialisms.contains(word) {
                let dotted = word.map { String($0) }.joined(separator: ".") + "."
                result = (result as NSString).replacingCharacters(in: match.range, with: dotted)
            }
        }
        return result
    }
    
    static func normalizeCurrencies(_ text: String) -> String {
        var result = text
        
        // $1.2M -> 1.2 million dollars
        let unitPattern = "\\$(\\d+(?:\\.\\d+)?)([KMB])\\b"
        if let regex = try? NSRegularExpression(pattern: unitPattern) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                let amount = nsString.substring(with: match.range(at: 1))
                let unit = nsString.substring(with: match.range(at: 2))
                
                let unitWord: String
                switch unit {
                case "K": unitWord = "thousand"
                case "M": unitWord = "million"
                case "B": unitWord = "billion"
                default: unitWord = ""
                }
                
                let replaced = "\(amount) \(unitWord) dollars"
                result = (result as NSString).replacingCharacters(in: match.range, with: replaced)
            }
        }
        
        // $100 -> 100 dollars
        let dollarPattern = "\\$(\\d+(?:\\.\\d+)?)\\b"
        if let dollarRegex = try? NSRegularExpression(pattern: dollarPattern) {
            let nsStr = result as NSString
            let dollarMatches = dollarRegex.matches(in: result, range: NSRange(location: 0, length: nsStr.length))
            for match in dollarMatches.reversed() {
                let amount = nsStr.substring(with: match.range(at: 1))
                let replaced = "\(amount) dollars"
                result = (result as NSString).replacingCharacters(in: match.range, with: replaced)
            }
        }
        
        return result
    }
    
    static func normalizeDates(_ text: String) -> String {
        let pattern = "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        
        var result = text
        for match in matches.reversed() {
            let year = nsString.substring(with: match.range(at: 1))
            let month = nsString.substring(with: match.range(at: 2))
            let day = nsString.substring(with: match.range(at: 3))
            
            var components = DateComponents()
            components.year = Int(year)
            components.month = Int(month)
            components.day = Int(day)
            
            if let date = Calendar.current.date(from: components) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US")
                formatter.dateStyle = .long
                formatter.timeStyle = .none
                let dateString = formatter.string(from: date)
                result = (result as NSString).replacingCharacters(in: match.range, with: dateString)
            }
        }
        return result
    }
    
    static func stripMarkdown(_ text: String) -> String {
        var result = text
        
        // [text](url) -> text
        let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        if let regex = try? NSRegularExpression(pattern: linkPattern) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                let linkText = nsString.substring(with: match.range(at: 1))
                result = (result as NSString).replacingCharacters(in: match.range, with: linkText)
            }
        }
        
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "_", with: "")
        result = result.replacingOccurrences(of: "`", with: "")
        
        return result
    }
    
    static func extractParagraphsFromHTML(_ html: String) -> [String] {
        guard let doc = try? SwiftSoup.parse(html), let body = doc.body() else { return [] }
        var paragraphs = [String]()
        
        do {
            let elements = try body.select("p, div, blockquote, aside, h1, h2, h3, h4, h5, h6, li")
            for el in elements {
                // Heuristic: If this element has any descendant of the same block tags,
                // we skip it because those descendants will be processed individually.
                let hasBlockDescendants = try !el.select("p, div, blockquote, aside, h1, h2, h3, h4, h5, h6, li").isEmpty
                if hasBlockDescendants {
                    continue
                }
                
                let prefix = el.ttsPrefix()
                let text = try el.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    let combined = prefix + text
                    if !paragraphs.contains(combined) {
                        paragraphs.append(combined)
                    }
                }
            }
        } catch {
            print("[Paragraph Extraction] Error: \(error)")
        }
        
        if paragraphs.isEmpty {
            if let text = try? body.text() {
                paragraphs = text.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        
        return paragraphs
    }
}
