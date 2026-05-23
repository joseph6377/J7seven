import Foundation
import SwiftUI

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
}

struct ChapterText: Codable, Identifiable {
    let index: Int
    let title: String
    let paragraphs: [String]      // plain text, pre-split
    
    var id: Int { index }
}

struct PlaybackCursor: Codable {
    var chapterIndex: Int = 0
    var paragraphIndex: Int = 0      // paragraph user last reached
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
}

extension LibraryEntry {
    init(from doc: SavedDocument) {
        id = doc.id
        title = doc.title
        author = doc.author
        lastOpenedAt = doc.lastOpenedAt

        // Calculate progress based on paragraphs
        let totalParagraphs = doc.chapters.reduce(0) { $0 + $1.paragraphs.count }
        if totalParagraphs > 0 {
            let before = doc.chapters
                .prefix(doc.cursor.chapterIndex)
                .reduce(0) { $0 + $1.paragraphs.count }
            progress = Double(before + doc.cursor.paragraphIndex) / Double(totalParagraphs)
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
                    remainingWords += paragraph.split(separator: " ").count
                }
            } else {
                for paragraph in chapter.paragraphs {
                    remainingWords += paragraph.split(separator: " ").count
                }
            }
        }

        // 150 WPM average audiobook speaking speed
        let wordsPerMinute = 150.0
        let totalMinutes = Double(remainingWords) / wordsPerMinute
        let hours = Int(totalMinutes / 60.0)
        let mins = Int(totalMinutes.truncatingRemainder(dividingBy: 60.0))

        if hours > 0 {
            estimatedTimeLeft = "\(hours) hrs left"
        } else if mins > 0 {
            estimatedTimeLeft = "\(mins) mins left"
        } else {
            estimatedTimeLeft = "Finished"
        }

        // Calculate words read for duration estimation (real-world actual hours read/listened)
        var wordsRead = 0
        for (cIdx, chapter) in doc.chapters.enumerated() {
            if cIdx < doc.cursor.chapterIndex {
                for paragraph in chapter.paragraphs {
                    wordsRead += paragraph.split(separator: " ").count
                }
            } else if cIdx == doc.cursor.chapterIndex {
                let readParagraphs = chapter.paragraphs.prefix(min(doc.cursor.paragraphIndex, chapter.paragraphs.count))
                for paragraph in readParagraphs {
                    wordsRead += paragraph.split(separator: " ").count
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
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.striped.horizontal"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

import NaturalLanguage

extension SavedDocument {
    var detectedLanguage: String {
        let recognizer = NLLanguageRecognizer()
        var sampleText = ""
        var count = 0
        for chapter in chapters {
            for paragraph in chapter.paragraphs {
                sampleText += paragraph + " "
                count += 1
                if count >= 6 { break }
            }
            if count >= 6 { break }
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
