import Foundation

struct LibraryEntry: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let author: String
    let cover: String?
    let duration: Double
    let chapterCount: Int
}

extension LibraryEntry {
    init(from manifest: BookManifest) {
        id           = manifest.id
        slug         = manifest.slug
        title        = manifest.title
        author       = manifest.author
        cover        = manifest.cover
        duration     = manifest.duration > 0 ? manifest.duration : manifest.chapters.reduce(0) { $0 + $1.duration }
        chapterCount = manifest.chapters.count
    }
}

struct BookManifest: Codable, Identifiable {
    let id: String
    let slug: String
    let title: String
    let author: String
    let cover: String?
    let duration: Double
    let chapters: [Chapter]
}

struct Chapter: Codable, Identifiable {
    let title: String
    let slug: String
    let audio: String
    let html: String
    let duration: Double
    let paragraphs: [Paragraph]

    var id: String { slug }
}

struct Paragraph: Codable, Identifiable {
    let id: String
    let start: Double
    let end: Double
    let wordEnds: [Double]
}

struct ReadingProgress: Codable {
    var chapterIdx: Int = 0
    var time: Double = 0
    var updatedAt: Date = .now
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
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
