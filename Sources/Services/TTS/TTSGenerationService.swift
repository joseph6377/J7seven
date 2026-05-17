import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

enum GenerationState: Equatable {
    case idle
    case preparingModel
    case generating(chapter: Int, paragraph: Int, totalParagraphs: Int)
    case paused
    case finalizingAudio
    case done(slug: String)
    case failed(String)
}

/// Snapshot of a book mid-generation so the UI can offer playback of completed chapters.
struct LiveBookInfo {
    let slug: String
    let title: String
    let author: String
    let coverFilename: String?   // relative to BookPaths.bookDirectory
    let chapterTitles: [String]
}

@Observable
@MainActor
final class TTSGenerationService {

    var state: GenerationState = .idle

    /// True once the first paragraph buffer is ready — enables "Listen Now".
    var canPlayNow: Bool = false

    /// Set when generation starts; cleared on completion or cancel.
    var liveBook: LiveBookInfo?

    /// How many chapters have been fully encoded to M4A so far.
    var completedChapterCount: Int = 0

    /// Convenience — true whenever generation is in progress or paused.
    var isActive: Bool {
        switch state {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    let supertonicService: SupertonicService
    private var generationTask: Task<Void, Never>?
    private var isPaused = false

    // AVAudioEngine for immediate gapless playback during synthesis
    private let engine      = AVAudioEngine()
    private let playerNode  = AVAudioPlayerNode()
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 44100, channels: 1, interleaved: false
    )!

    init(supertonicService: SupertonicService) {
        self.supertonicService = supertonicService
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
        try? engine.start()
    }

    // MARK: - Public API

    /// `selectedIndices` — which EPUB chapter indices to synthesise (nil = all).
    func generate(epubURL: URL, voice: TTSVoice, selectedIndices: Set<Int>? = nil) {
        guard case .idle = state else { return }
        isPaused = false
        generationTask = Task { await runGeneration(epubURL: epubURL, voice: voice, selectedIndices: selectedIndices) }
    }

    func pause() {
        isPaused = true
        playerNode.pause()
        if case .generating = state { state = .paused }
    }

    func resume() {
        isPaused = false
        playerNode.play()
    }

    func cancel() {
        generationTask?.cancel()
        engine.stop()
        state = .idle
        canPlayNow = false
        liveBook = nil
        completedChapterCount = 0
    }

    // MARK: - Generation pipeline

    private func runGeneration(epubURL: URL, voice: TTSVoice, selectedIndices: Set<Int>?) async {
        // 1. Parse EPUB text
        let book: EpubTextParser.ParsedBook
        do {
            book = try EpubTextParser.parse(epubURL: epubURL)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        let slug = book.slug

        // Write cover immediately so PlayerView can show it during live playback
        var coverFilename: String? = nil
        if let coverData = book.coverData {
            let bookDir = BookPaths.bookDirectory(slug: slug)
            let coverURL = bookDir.appendingPathComponent("cover.jpg")
            try? coverData.write(to: coverURL)
            coverFilename = "cover.jpg"
        }

        // Filter to selected chapters only (re-indexed 0..N-1)
        let selectedChapters: [EpubChapter]
        if let indices = selectedIndices {
            selectedChapters = book.chapters.enumerated()
                .filter { indices.contains($0.offset) }
                .map(\.element)
        } else {
            selectedChapters = book.chapters
        }

        // Expose book info so the banner can offer completed-chapter playback
        liveBook = LiveBookInfo(
            slug:          slug,
            title:         book.title,
            author:        book.author,
            coverFilename: coverFilename,
            chapterTitles: selectedChapters.map(\.title)
        )
        completedChapterCount = 0

        // Write stub manifest immediately → book appears in library before any chapter encodes
        let writer = M4AWriter(
            slug: slug, title: book.title, author: book.author,
            coverData: book.coverData,
            chapterTitles: selectedChapters.map(\.title)
        )
        try? writer.writeInitialManifest()

        // 2. Ensure model is ready
        state = .preparingModel
        if case .notDownloaded = supertonicService.modelState {
            do { try await supertonicService.downloadModel() }
            catch { state = .failed(error.localizedDescription); return }
        }

        // 3. Resume from saved progress if available
        var progress = TTSProgress.load(slug: slug)
                       ?? TTSProgress(slug: slug, voiceId: voice.id)

        // 4. Request background execution time so iOS doesn't suspend mid-synthesis
        #if canImport(UIKit)
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(bgTask)
        }
        defer { UIApplication.shared.endBackgroundTask(bgTask) }
        #endif

        // 5. Synthesis loop — paragraph by paragraph, chapter by chapter
        for (chIdx, chapter) in selectedChapters.enumerated() {
            let total = chapter.paragraphs.count

            for (pIdx, text) in chapter.paragraphs.enumerated() {
                if Task.isCancelled { return }

                while isPaused {
                    try? await Task.sleep(for: .milliseconds(200))
                    if Task.isCancelled { return }
                }

                // Skip paragraphs already synthesised in a previous run
                if progress.isCompleted(chapterIdx: chIdx, paragraphIdx: pIdx) { continue }

                state = .generating(chapter: chIdx, paragraph: pIdx, totalParagraphs: total)

                let buffer: AVAudioPCMBuffer
                do {
                    buffer = try await supertonicService.synthesize(text: text, voice: voice)
                } catch {
                    // Skip bad paragraphs rather than aborting the whole book
                    print("TTS skipped ch\(chIdx)-p\(pIdx): \(error.localizedDescription)")
                    continue
                }

                // Schedule buffer for immediate gapless playback
                await playerNode.scheduleBuffer(buffer)
                if !playerNode.isPlaying { playerNode.play() }
                canPlayNow = true

                // Cache WAV to disk for later M4A encoding
                let wavPath = saveTempWAV(buffer: buffer, chIdx: chIdx, pIdx: pIdx, slug: slug)
                progress.completedParagraphs.append(
                    TTSProgress.CompletedParagraph(
                        chapterIdx: chIdx, paragraphIdx: pIdx, tempWavPath: wavPath
                    )
                )
                try? progress.save()
            }

            // Encode all paragraphs for this chapter → single M4A file
            let wavPaths = progress.wavPaths(forChapter: chIdx)
            try? writer.finalizeChapter(chIdx, wavPaths: wavPaths)
            try? writer.writePartialManifest()   // book appears in library immediately
            completedChapterCount = chIdx + 1
        }

        // 6. Write manifest.json + cover → book appears in library
        state = .finalizingAudio
        do {
            try writer.finalizeBook()
            TTSProgress.delete(slug: slug)
            cleanupTempWAVs(slug: slug)
            liveBook = nil
            completedChapterCount = 0
            state = .done(slug: slug)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Temp WAV helpers

    private func saveTempWAV(buffer: AVAudioPCMBuffer, chIdx: Int, pIdx: Int, slug: String) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts-\(slug)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("ch\(chIdx)-p\(pIdx).wav")
        if let file = try? AVAudioFile(forWriting: url, settings: buffer.format.settings) {
            try? file.write(from: buffer)
        }
        return url.path
    }

    private func cleanupTempWAVs(slug: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts-\(slug)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}
