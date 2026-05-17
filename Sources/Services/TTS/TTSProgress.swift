import Foundation

/// Persisted synthesis progress — saved after each paragraph so generation
/// can resume if the app is suspended or the user pauses mid-book.
struct TTSProgress: Codable {
    let slug: String
    let voiceId: String
    var completedParagraphs: [CompletedParagraph] = []

    struct CompletedParagraph: Codable {
        let chapterIdx: Int
        let paragraphIdx: Int
        let paragraphId: String    // matches <p id=""> in HTML and Paragraph.id in manifest
        let startTime: Double      // cumulative seconds within chapter
        let endTime: Double
        let tempWavPath: String    // absolute path to cached WAV on disk
    }

    // MARK: - Persistence

    private static func progressURL(slug: String) -> URL {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tts-progress", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(slug).json")
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: TTSProgress.progressURL(slug: slug), options: .atomic)
    }

    static func load(slug: String) -> TTSProgress? {
        let url = progressURL(slug: slug)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TTSProgress.self, from: data)
    }

    static func delete(slug: String) {
        try? FileManager.default.removeItem(at: progressURL(slug: slug))
    }

    func isCompleted(chapterIdx: Int, paragraphIdx: Int) -> Bool {
        completedParagraphs.contains {
            $0.chapterIdx == chapterIdx && $0.paragraphIdx == paragraphIdx
        }
    }
}
