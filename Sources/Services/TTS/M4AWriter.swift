import Foundation
import AVFoundation

/// Converts per-chapter synthesis output into BooksApp library format:
///   Documents/books/[slug]/
///     manifest.json   ← written immediately as stub, updated after each chapter
///     cover.jpg
///     ch-0.m4a
///     ch-1.m4a  ...
final class M4AWriter {

    private let slug: String
    private let title: String
    private let author: String
    private let coverData: Data?
    private let chapterTitles: [String]
    private var finalisedChapters: [FinalisedChapter] = []

    private struct FinalisedChapter {
        let index: Int
        let duration: Double
    }

    private var bookDir: URL { BookPaths.bookDirectory(slug: slug) }

    init(slug: String, title: String, author: String,
         coverData: Data?, chapterTitles: [String]) {
        self.slug          = slug
        self.title         = title
        self.author        = author
        self.coverData     = coverData
        self.chapterTitles = chapterTitles
    }

    // MARK: - Initial stub manifest

    /// Write manifest.json immediately with ALL chapters as stubs (duration = 0, audio path
    /// pre-assigned). Lets the library show the book before any chapter is encoded.
    func writeInitialManifest() throws {
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(buildManifest(stubsForPending: true))
        try data.write(to: bookDir.appendingPathComponent("manifest.json"), options: .atomic)
    }

    // MARK: - Per-chapter finalisation

    func finalizeChapter(_ idx: Int, wavPaths: [String]) throws {
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        let m4aURL = bookDir.appendingPathComponent("ch-\(idx).m4a")
        let duration = try encodeToM4A(wavPaths: wavPaths, outputURL: m4aURL)
        finalisedChapters.append(FinalisedChapter(index: idx, duration: duration))
    }

    /// Overwrites manifest.json: finalised chapters get real duration, pending ones keep
    /// the stub entry (duration 0) so the library row stays visible while generating.
    func writePartialManifest() throws {
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(buildManifest(stubsForPending: true))
        try data.write(to: bookDir.appendingPathComponent("manifest.json"), options: .atomic)
    }

    // MARK: - Book finalisation

    func finalizeBook() throws {
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        if let coverData {
            try coverData.write(to: bookDir.appendingPathComponent("cover.jpg"))
        }
        // Final manifest: only chapters that were actually encoded (no stubs)
        let data = try JSONEncoder().encode(buildManifest(stubsForPending: false))
        try data.write(to: bookDir.appendingPathComponent("manifest.json"), options: .atomic)
    }

    // MARK: - Manifest builder

    private func buildManifest(stubsForPending: Bool) -> BookManifest {
        let durationMap = Dictionary(uniqueKeysWithValues: finalisedChapters.map { ($0.index, $0.duration) })

        var chapters: [Chapter] = []
        for (idx, title) in chapterTitles.enumerated() {
            if let dur = durationMap[idx] {
                chapters.append(Chapter(title: title, slug: "ch-\(idx)",
                                        audio: "ch-\(idx).m4a", html: "", duration: dur, paragraphs: []))
            } else if stubsForPending {
                // Stub: audio filename is pre-assigned but file doesn't exist yet
                chapters.append(Chapter(title: title, slug: "ch-\(idx)",
                                        audio: "ch-\(idx).m4a", html: "", duration: 0, paragraphs: []))
            }
        }

        return BookManifest(
            id:       slug,
            slug:     slug,
            title:    title,
            author:   author,
            cover:    coverData != nil ? "cover.jpg" : nil,
            duration: chapters.reduce(0) { $0 + $1.duration },
            chapters: chapters
        )
    }

    // MARK: - WAV → M4A

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
            let cap    = AVAudioFrameCount(inFile.length)
            guard let buf = AVAudioPCMBuffer(pcmFormat: inFile.processingFormat,
                                             frameCapacity: cap) else { continue }
            try inFile.read(into: buf)
            try outFile.write(from: buf)
            totalFrames += inFile.length
        }
        return Double(totalFrames) / 44100.0
    }
}
