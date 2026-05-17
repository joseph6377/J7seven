import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

enum GenerationState {
    case idle
    case preparingModel
    case generating(chapter: Int, paragraph: Int, totalParagraphs: Int)
    case paused
    case finalizingAudio
    case done(slug: String)
    case failed(String)
}

@Observable
@MainActor
final class TTSGenerationService {

    var state: GenerationState = .idle

    /// True once the first paragraph buffer is ready — enables "Listen Now".
    var canPlayNow: Bool = false

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

    func generate(epubURL: URL, voice: TTSVoice) {
        guard case .idle = state else { return }
        isPaused = false
        generationTask = Task { await runGeneration(epubURL: epubURL, voice: voice) }
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
    }

    // MARK: - Generation pipeline

    private func runGeneration(epubURL: URL, voice: TTSVoice) async {
        // 1. Parse EPUB text
        let book: EpubTextParser.ParsedBook
        do {
            book = try EpubTextParser.parse(epubURL: epubURL)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        let slug = book.slug

        // 2. Ensure model is ready
        state = .preparingModel
        if case .notDownloaded = supertonicService.modelState {
            do { try await supertonicService.downloadModel() }
            catch { state = .failed(error.localizedDescription); return }
        }

        // 3. Resume from saved progress if available
        var progress = TTSProgress.load(slug: slug)
                       ?? TTSProgress(slug: slug, voiceId: voice.id)

        let writer = M4AWriter(
            slug: slug, title: book.title, author: book.author,
            coverData: book.coverData,
            chapterTitles: book.chapters.map(\.title)
        )

        // 4. Request background execution time so iOS doesn't suspend mid-synthesis
        #if canImport(UIKit)
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(bgTask)
        }
        defer { UIApplication.shared.endBackgroundTask(bgTask) }
        #endif

        // 5. Synthesis loop — paragraph by paragraph, chapter by chapter
        for (chIdx, chapter) in book.chapters.enumerated() {
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
                playerNode.scheduleBuffer(buffer)
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
        }

        // 6. Write manifest.json + cover → book appears in library
        state = .finalizingAudio
        do {
            try writer.finalizeBook()
            TTSProgress.delete(slug: slug)
            cleanupTempWAVs(slug: slug)
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
