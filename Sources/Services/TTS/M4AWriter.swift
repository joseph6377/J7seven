import Foundation
import AVFoundation

/// Converts per-paragraph synthesis output into BooksApp library format:
///   Documents/books/[slug]/
///     manifest.json
///     cover.jpg          (if extracted)
///     ch-0.m4a
///     ch-0.html
///     ch-1.m4a  ...
final class M4AWriter {

    private let slug: String
    private let title: String
    private let author: String
    private let coverData: Data?
    private let chapters: [EpubChapter]
    private var finalisedChapters: [FinalisedChapter] = []

    private struct FinalisedChapter {
        let index: Int
        let title: String
        let duration: Double
        let paragraphs: [TTSProgress.CompletedParagraph]
    }

    private var bookDir: URL {
        BookPaths.bookDirectory(slug: slug)
    }

    init(slug: String, title: String, author: String,
         coverData: Data?, chapters: [EpubChapter]) {
        self.slug      = slug
        self.title     = title
        self.author    = author
        self.coverData = coverData
        self.chapters  = chapters
    }

    // MARK: - Per-chapter finalisation

    /// Call after all paragraphs in a chapter are synthesised.
    func finalizeChapter(_ idx: Int, paragraphs: [TTSProgress.CompletedParagraph]) throws {
        guard idx < chapters.count else { return }
        let chapter   = chapters[idx]
        let chDuration = paragraphs.map(\.endTime).max() ?? 0

        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

        let m4aURL = bookDir.appendingPathComponent("ch-\(idx).m4a")
        try encodeToM4A(paragraphs: paragraphs, outputURL: m4aURL)

        let htmlURL = bookDir.appendingPathComponent("ch-\(idx).html")
        let html    = generateHTML(chapterIdx: idx, paragraphs: paragraphs,
                                   texts: chapter.paragraphs)
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)

        finalisedChapters.append(FinalisedChapter(index: idx, title: chapter.title,
                                                   duration: chDuration,
                                                   paragraphs: paragraphs))
    }

    // MARK: - Book finalisation

    func finalizeBook() throws {
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

        if let coverData {
            try coverData.write(to: bookDir.appendingPathComponent("cover.jpg"))
        }

        let sorted = finalisedChapters.sorted { $0.index < $1.index }
        let manifestChapters: [Chapter] = sorted.map { ch in
            let paras = ch.paragraphs.map { p in
                Paragraph(id: p.paragraphId, start: p.startTime, end: p.endTime, wordEnds: [])
            }
            return Chapter(title: ch.title, slug: "ch-\(ch.index)",
                           audio: "ch-\(ch.index).m4a", html: "ch-\(ch.index).html",
                           duration: ch.duration, paragraphs: paras)
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

    private func encodeToM4A(paragraphs: [TTSProgress.CompletedParagraph],
                              outputURL: URL) throws {
        // TODO: Implement AVAssetWriter-based encoding.
        //
        // Option A — AVAudioFile / AVAudioConverter (simpler):
        //   let aacSettings: [String: Any] = [
        //       AVFormatIDKey:         kAudioFormatMPEG4AAC,
        //       AVSampleRateKey:       44100,
        //       AVNumberOfChannelsKey: 1,
        //       AVEncoderBitRateKey:   64_000
        //   ]
        //   let outFile = try AVAudioFile(forWriting: outputURL, settings: aacSettings)
        //   for p in paragraphs {
        //       let wavFile = try AVAudioFile(forReading: URL(fileURLWithPath: p.tempWavPath))
        //       let buf = AVAudioPCMBuffer(pcmFormat: wavFile.processingFormat,
        //                                  frameCapacity: AVAudioFrameCount(wavFile.length))!
        //       try wavFile.read(into: buf)
        //       // convert pcm → aac then write — use AVAudioConverter
        //       try outFile.write(from: buf)
        //   }
        //
        // Option B — AVAssetWriter (more control, chapter markers possible):
        //   Convert each AVAudioPCMBuffer → CMSampleBuffer, feed to AVAssetWriterInput.
        //   See Apple docs for AVAudioPCMBuffer → CMSampleBuffer pattern.
        //
        // Note: Test Option A first — it's much simpler and sufficient for the use case.

        throw NSError(domain: "M4AWriter", code: 0,
                      userInfo: [NSLocalizedDescriptionKey: "TODO: implement WAV→M4A encoding"])
    }

    // MARK: - HTML generation

    private func generateHTML(chapterIdx: Int,
                               paragraphs: [TTSProgress.CompletedParagraph],
                               texts: [String]) -> String {
        var lines = ["<!DOCTYPE html><html><body>"]
        for (i, para) in paragraphs.enumerated() {
            let text = i < texts.count ? texts[i].xmlEscaped : ""
            lines.append("<p id=\"\(para.paragraphId)\">\(text)</p>")
        }
        lines.append("</body></html>")
        return lines.joined(separator: "\n")
    }
}

private extension String {
    var xmlEscaped: String {
        self.replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
