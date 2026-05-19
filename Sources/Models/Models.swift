import Foundation

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
}

extension LibraryEntry {
    init(from doc: SavedDocument) {
        id = doc.id
        title = doc.title
        author = doc.author
        lastOpenedAt = doc.lastOpenedAt
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
