import Foundation
import AVFoundation
import UIKit

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

    /// True once the first paragraph is synthesised — enables "Listen Now".
    var canPlayNow: Bool = false

    /// The paragraph ID currently being read aloud (maps to PlayerService.currentParagraphId).
    var currentlyPlayingParagraphId: String? = nil

    /// Convenience for the UI — true whenever generation is in progress or paused.
    var isActive: Bool {
        switch state {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    let supertonicService: SupertonicService
    private var generationTask: Task<Void, Never>?
    private var isPaused = false

    // Audio engine for immediate gapless playback
    private let engine      = AVAudioEngine()
    private let playerNode  = AVAudioPlayerNode()
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                              sampleRate: 44100, channels: 1, interleaved: false)!

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
        // Generation loop polls isPaused and continues automatically
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

        let writer = M4AWriter(slug: slug, title: book.title, author: book.author,
                               coverData: book.coverData, chapters: book.chapters)

        // 4. Request background execution time
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(bgTask)
        }
        defer { UIApplication.shared.endBackgroundTask(bgTask) }

        // 5. Synthesis loop
        for (chIdx, chapter) in book.chapters.enumerated() {
            let total = chapter.paragraphs.count

            for (pIdx, text) in chapter.paragraphs.enumerated() {
                if Task.isCancelled { return }

                while isPaused {
                    try? await Task.sleep(for: .milliseconds(200))
                    if Task.isCancelled { return }
                }

                // Skip paragraphs already done in a previous run
                if progress.isCompleted(chapterIdx: chIdx, paragraphIdx: pIdx) { continue }

                state = .generating(chapter: chIdx, paragraph: pIdx, totalParagraphs: total)

                let paraId = "\(slug)-ch\(chIdx)-p\(pIdx)"

                let buffer: AVAudioPCMBuffer
                do {
                    buffer = try await supertonicService.synthesize(text: text, voice: voice)
                } catch {
                    print("TTS skipped \(paraId): \(error.localizedDescription)")
                    continue
                }

                // Schedule buffer for immediate gapless playback
                let capturedId = paraId
                playerNode.scheduleBuffer(buffer) { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.currentlyPlayingParagraphId = capturedId
                    }
                }
                if !playerNode.isPlaying { playerNode.play() }
                canPlayNow = true

                // Save temp WAV + progress
                let wavPath = saveTempWAV(buffer: buffer, paraId: paraId)
                let chStart = progress.completedParagraphs
                    .filter { $0.chapterIdx == chIdx }
                    .map(\.endTime).max() ?? 0
                let duration = Double(buffer.frameLength) / buffer.format.sampleRate
                let completed = TTSProgress.CompletedParagraph(
                    chapterIdx: chIdx, paragraphIdx: pIdx,
                    paragraphId: paraId,
                    startTime: chStart, endTime: chStart + duration,
                    tempWavPath: wavPath
                )
                progress.completedParagraphs.append(completed)
                try? progress.save()
            }

            // Finalise chapter → M4A + HTML
            let chParas = progress.completedParagraphs.filter { $0.chapterIdx == chIdx }
            try? writer.finalizeChapter(chIdx, paragraphs: chParas)
        }

        // 6. Write manifest.json + cover → book appears in library
        state = .finalizingAudio
        do {
            try writer.finalizeBook()
            TTSProgress.delete(slug: slug)
            state = .done(slug: slug)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Temp WAV save

    private func saveTempWAV(buffer: AVAudioPCMBuffer, paraId: String) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts-wav", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(paraId).wav")
        // TODO: Write buffer to WAV using AVAudioFile
        // let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        // try file.write(from: buffer)
        return url.path
    }
}
