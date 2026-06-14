import Foundation
import SwiftUI

struct Paragraph: Codable, Equatable, Hashable {
    let text: String
    let pageNumber: Int?  // nil for EPUB, set for PDF
}

enum SourceFormat: String, Codable {
    case epub, pdf, web, pastedText
}

// Persisted (text + cursor only — no audio)
struct SavedDocument: Codable, Identifiable {
    let id: UUID                  // stable ID, used as filename
    let title: String
    let author: String?
    let coverImageData: Data?     // small JPEG, ≤200 KB, optional
    let importedAt: Date
    var lastOpenedAt: Date
    var chapters: [ChapterText]   // text only
    var cursor: PlaybackCursor
    let sourceFormat: SourceFormat?
    let pageCount: Int?
    let sourceURL: URL?

    var format: SourceFormat {
        sourceFormat ?? .epub
    }

    init(
        id: UUID,
        title: String,
        author: String?,
        coverImageData: Data?,
        importedAt: Date,
        lastOpenedAt: Date,
        chapters: [ChapterText],
        cursor: PlaybackCursor,
        sourceFormat: SourceFormat? = .epub,
        pageCount: Int? = nil,
        sourceURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImageData = coverImageData
        self.importedAt = importedAt
        self.lastOpenedAt = lastOpenedAt
        self.chapters = chapters
        self.cursor = cursor
        self.sourceFormat = sourceFormat
        self.pageCount = pageCount
        self.sourceURL = sourceURL
    }
}

struct ChapterText: Codable, Identifiable {
    let index: Int
    let title: String
    let paragraphs: [Paragraph]      // plain text, pre-split

    var id: Int { index }

    // Builds a chapter whose title is prepended as the first paragraph so TTS
    // speaks the heading. First strips any leading body paragraphs that merely
    // restate the title (books often embed the chapter number/name in the body,
    // sometimes split across lines), then prepends a single clean title unless
    // the remaining body already opens with it — so the title isn't shown or
    // read twice.
    static func withSpokenTitle(index: Int, title: String, paragraphs: [Paragraph]) -> ChapterText {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return ChapterText(index: index, title: title, paragraphs: paragraphs)
        }

        let body = stripRedundantTitle(from: paragraphs, title: trimmedTitle)

        let firstMatchesTitle = body.first.map {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmedTitle) == .orderedSame
        } ?? false
        guard !firstMatchesTitle else {
            return ChapterText(index: index, title: title, paragraphs: body)
        }
        let titleParagraph = Paragraph(text: trimmedTitle, pageNumber: body.first?.pageNumber)
        return ChapterText(index: index, title: title, paragraphs: [titleParagraph] + body)
    }

    /// Drops leading paragraphs that together reconstruct the chapter title.
    /// Conservative: only strips when the consumed paragraphs *exactly* rebuild
    /// the title's word tokens (optionally ignoring a leading chapter number),
    /// never strips on a partial overlap, and never strips the body to empty.
    private static func stripRedundantTitle(from paragraphs: [Paragraph], title: String) -> [Paragraph] {
        let titleTokens = titleWordTokens(title)
        guard !titleTokens.isEmpty else { return paragraphs }
        // Variant with a leading number / "chapter" dropped, so a body that
        // embeds only the title name (no number) still matches.
        let coreTokens = droppingLeadingNumberTokens(titleTokens)

        var acc: [String] = []
        var consumed = 0
        for (i, para) in paragraphs.enumerated() {
            if i >= 4 { break }                       // only inspect the opening lines
            let tokens = titleWordTokens(para.text)
            if tokens.isEmpty { continue }            // ignore blank separators
            let candidate = acc + tokens
            if isPrefix(candidate, of: titleTokens) || isPrefix(candidate, of: coreTokens) {
                acc = candidate
                consumed = i + 1
                if acc == titleTokens || acc == coreTokens { break }
            } else {
                break
            }
        }

        guard consumed > 0, acc == titleTokens || acc == coreTokens else { return paragraphs }
        let remaining = Array(paragraphs.dropFirst(consumed))
        return remaining.isEmpty ? paragraphs : remaining
    }

    /// Lowercased alphanumeric word tokens, e.g. "1. A Painter Prince" → ["1","a","painter","prince"].
    private static func titleWordTokens(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func droppingLeadingNumberTokens(_ tokens: [String]) -> [String] {
        var out = tokens
        while let first = out.first, first == "chapter" || first.allSatisfy(\.isNumber) {
            out.removeFirst()
        }
        return out
    }

    private static func isPrefix(_ candidate: [String], of tokens: [String]) -> Bool {
        candidate.count <= tokens.count && Array(tokens.prefix(candidate.count)) == candidate
    }
}

struct PlaybackCursor: Codable, Equatable {
    var chapterIndex: Int = 0
    var paragraphIndex: Int = 0      // paragraph user last reached
    var characterOffset: Int = 0     // character offset within paragraph
    
    enum CodingKeys: String, CodingKey {
        case chapterIndex
        case paragraphIndex
        case characterOffset
    }
    
    init(chapterIndex: Int = 0, paragraphIndex: Int = 0, characterOffset: Int = 0) {
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.characterOffset = characterOffset
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chapterIndex = try container.decodeIfPresent(Int.self, forKey: .chapterIndex) ?? 0
        self.paragraphIndex = try container.decodeIfPresent(Int.self, forKey: .paragraphIndex) ?? 0
        self.characterOffset = try container.decodeIfPresent(Int.self, forKey: .characterOffset) ?? 0
    }
}

// Minimal entry for the library list
struct LibraryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let author: String?
    let lastOpenedAt: Date
    let progress: Double
    let estimatedTimeLeft: String
    let durationRead: Double
    let format: SourceFormat?
    let wordCount: Int?
}

extension LibraryEntry {
    init(from doc: SavedDocument) {
        id = doc.id
        title = doc.title
        author = doc.author
        lastOpenedAt = doc.lastOpenedAt
        format = doc.format

        var totalWords = 0
        for chapter in doc.chapters {
            for paragraph in chapter.paragraphs {
                totalWords += paragraph.text.split(separator: " ").count
            }
        }
        wordCount = totalWords

        // Calculate progress based on paragraphs, accounting for firstIsTitle to prevent misleading progress on title reading
        let firstChapter = doc.chapters.first
        let firstIsTitle = firstChapter != nil && !firstChapter!.paragraphs.isEmpty &&
            firstChapter!.paragraphs[0].text.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(doc.title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame

        let totalParagraphs = doc.chapters.reduce(0) { $0 + $1.paragraphs.count }
        if totalParagraphs > 0 {
            if firstIsTitle && totalParagraphs > 1 {
                let adjustedTotal = totalParagraphs - 1
                let before = doc.chapters
                    .prefix(doc.cursor.chapterIndex)
                    .reduce(0) { $0 + $1.paragraphs.count }
                let currentPos = before + doc.cursor.paragraphIndex
                let adjustedPos = max(0, currentPos - 1)
                progress = Double(adjustedPos) / Double(adjustedTotal)
            } else {
                let before = doc.chapters
                    .prefix(doc.cursor.chapterIndex)
                    .reduce(0) { $0 + $1.paragraphs.count }
                progress = Double(before + doc.cursor.paragraphIndex) / Double(totalParagraphs)
            }
        } else {
            progress = 0.0
        }

        // Calculate remaining words for duration estimation
        var remainingWords = 0
        for (cIdx, chapter) in doc.chapters.enumerated() {
            if cIdx < doc.cursor.chapterIndex {
                continue
            } else if cIdx == doc.cursor.chapterIndex {
                let remainingParagraphs = chapter.paragraphs.suffix(from: min(doc.cursor.paragraphIndex, chapter.paragraphs.count))
                for paragraph in remainingParagraphs {
                    remainingWords += paragraph.text.split(separator: " ").count
                }
            } else {
                for paragraph in chapter.paragraphs {
                    remainingWords += paragraph.text.split(separator: " ").count
                }
            }
        }

        // 150 WPM average audiobook speaking speed
        let wordsPerMinute = 150.0
        let totalMinutes = Double(remainingWords) / wordsPerMinute
        let hours = Int(totalMinutes / 60.0)
        let mins = Int(totalMinutes.rounded(.up).truncatingRemainder(dividingBy: 60.0))

        let lastChapter = doc.chapters.last
        let lastParaIndex = (lastChapter?.paragraphs.count ?? 1) - 1
        let isAtEnd = doc.cursor.chapterIndex >= doc.chapters.count - 1 && doc.cursor.paragraphIndex >= lastParaIndex && remainingWords == 0

        if isAtEnd || remainingWords == 0 {
            estimatedTimeLeft = "Finished"
        } else if hours > 0 {
            estimatedTimeLeft = "\(hours) hr\(hours > 1 ? "s" : "") \(mins) min\(mins != 1 ? "s" : "") left"
        } else if mins > 0 {
            estimatedTimeLeft = "\(mins) min\(mins != 1 ? "s" : "") left"
        } else {
            estimatedTimeLeft = "Under 1 min left"
        }

        // Calculate words read for duration estimation (real-world actual hours read/listened)
        var wordsRead = 0
        for (cIdx, chapter) in doc.chapters.enumerated() {
            if cIdx < doc.cursor.chapterIndex {
                for paragraph in chapter.paragraphs {
                    wordsRead += paragraph.text.split(separator: " ").count
                }
            } else if cIdx == doc.cursor.chapterIndex {
                let readParagraphs = chapter.paragraphs.prefix(min(doc.cursor.paragraphIndex, chapter.paragraphs.count))
                for paragraph in readParagraphs {
                    wordsRead += paragraph.text.split(separator: " ").count
                }
            }
        }
        
        // 150 WPM speaking speed (2.5 words per second)
        durationRead = Double(wordsRead) / (wordsPerMinute / 60.0)
    }
}

extension Double {
    var formattedDuration: String {
        let h = Int(self) / 3600
        let m = Int(self) % 3600 / 60
        let s = Int(self) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var formattedDurationLong: String {
        let h = Int(self) / 3600
        let m = Int(self) % 3600 / 60
        let s = Int(self) % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}

// App Theme selection matching system preferences
enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case light = "Light"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        return .light
    }

    var iconName: String {
        return "sun.max"
    }
}

enum ReadingTheme: String, CaseIterable, Identifiable, Codable {
    case modernBlue = "modernBlue"
    case warmIvory = "warmIvory"
    case soothingGreen = "soothingGreen"
    
    var id: String { rawValue }
    
    var preferredColorScheme: ColorScheme? {
        return .light
    }

    var iconName: String {
        switch self {
        case .modernBlue: return "sparkles"
        case .warmIvory: return "cup.and.saucer"
        case .soothingGreen: return "leaf"
        }
    }
    
    var displayTitle: String {
        switch self {
        case .modernBlue: return "Modern Blue"
        case .warmIvory: return "Warm Ivory"
        case .soothingGreen: return "Soothing Sage"
        }
    }
}

import NaturalLanguage

extension SavedDocument {
    var detectedLanguage: String {
        let recognizer = NLLanguageRecognizer()
        var sampleText = ""
        
        let totalChapters = chapters.count
        guard totalChapters > 0 else { return "en" }
        
        // Sample paragraphs from the middle of the book to avoid metadata headers or licenses
        let middleChapterIndex = totalChapters / 2
        let targetChapters = [
            chapters[middleChapterIndex],
            chapters[min(middleChapterIndex + 1, totalChapters - 1)]
        ]
        
        var count = 0
        for chapter in targetChapters {
            for paragraph in chapter.paragraphs {
                let text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count > 30 {
                    sampleText += text + " "
                    count += 1
                    if count >= 10 { break }
                }
            }
            if count >= 10 { break }
        }
        
        // Fall back to the first chapter if we didn't find enough substantial paragraphs in the middle
        if count < 3 {
            for paragraph in chapters[0].paragraphs {
                let text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count > 15 {
                    sampleText += text + " "
                    count += 1
                    if count >= 10 { break }
                }
            }
        }
        
        let trimmed = sampleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "en" }
        
        recognizer.processString(trimmed)
        if let language = recognizer.dominantLanguage {
            return String(language.rawValue.prefix(2))
        }
        return "en"
    }
}
