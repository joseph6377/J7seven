import Foundation
import AVFoundation

/// Converts per-chapter synthesis output (cached WAV files) into BooksApp library format:
///   Documents/books/[slug]/
///     manifest.json
///     cover.jpg          (if extracted)
///     ch-0.m4a
///     ch-1.m4a  ...
///
/// Pure audio — no HTML files, no paragraph timing, no text at all.
final class M4AWriter {

    private let slug: String
    private let title: String
    private let author: String
    private let coverData: Data?
    private let chapterTitles: [String]
    private var finalisedChapters: [FinalisedChapter] = []

    private struct FinalisedChapter {
        let index: Int
        let title: String
        let duration: Double
    }

    private var bookDir: URL {
        BookPaths.bookDirectory(slug: slug)
    }

    init(slug: String, title: String, author: String,
         coverData: Data?, chapterTitles: [String]) {
        self.slug          = slug
        self.title         = title
        self.author        = author
        self.coverData     = coverData
        self.chapterTitles = chapterTitles
    }

    // MARK: - Per-chapter finalisation

    /// Call after all paragraphs in a chapter are synthesised.
    /// `wavPaths` are the cached temp WAV files in paragraph order.
    func finalizeChapter(_ idx: Int, wavPaths: [String]) throws {
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

        let m4aURL = bookDir.appendingPathComponent("ch-\(idx).m4a")
        let duration = try encodeToM4A(wavPaths: wavPaths, outputURL: m4aURL)

        let title = idx < chapterTitles.count ? chapterTitles[idx] : "Chapter \(idx + 1)"
        finalisedChapters.append(FinalisedChapter(index: idx, title: title, duration: duration))
    }

    // MARK: - Book finalisation

    /// Call once all chapters are done. Writes manifest.json and cover image.
    func finalizeBook() throws {
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

        if let coverData {
            try coverData.write(to: bookDir.appendingPathComponent("cover.jpg"))
        }

        let sorted = finalisedChapters.sorted { $0.index < $1.index }
        let manifestChapters = sorted.map { ch in
            Chapter(
                title:      ch.title,
                slug:       "ch-\(ch.index)",
                audio:      "ch-\(ch.index).m4a",
                html:       "",           // pure audio — no reader
                duration:   ch.duration,
                paragraphs: []            // no text, no timing needed
            )
        }

        let manifest = BookManifest(
            id:       UUID().uuidString,
            slug:     slug,
            title:    title,
            author:   author,
            cover:    coverData != nil ? "cover.jpg" : nil,
            duration: sorted.reduce(0) { $0 + $1.duration },
            chapters: manifestChapters
        )

        let data = try JSONEncoder().encode(manifest)
        try data.write(to: bookDir.appendingPathComponent("manifest.json"), options: .atomic)
    }

    // MARK: - WAV → M4A encoding

    /// Concatenates all paragraph WAV files into a single M4A chapter file.
    /// Returns the total audio duration in seconds.
    @discardableResult
    private func encodeToM4A(wavPaths: [String], outputURL: URL) throws -> Double {
        let aacSettings: [String: Any] = [
            AVFormatIDKey:         kAudioFormatMPEG4AAC,
            AVSampleRateKey:       44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey:   64_000,
        ]
        let outFile = try AVAudioFile(forWriting: outputURL, settings: aacSettings)
        var totalFrames: AVAudioFramePosition = 0

        for path in wavPaths {
            let inURL  = URL(fileURLWithPath: path)
            let inFile = try AVAudioFile(forReading: inURL)
            let capacity = AVAudioFrameCount(inFile.length)
            guard let buf = AVAudioPCMBuffer(
                    pcmFormat: inFile.processingFormat,
                    frameCapacity: capacity) else { continue }
            try inFile.read(into: buf)
            try outFile.write(from: buf)    // AVAudioFile converts PCM→AAC internally
            totalFrames += inFile.length
        }

        return Double(totalFrames) / 44100.0
    }
}
