import Foundation
import AVFoundation
import Accelerate

@MainActor
final class SynthScheduler {
    private let synthesizer: Synthesizer
    private let player: PlayerService
    private let lookAhead: Int

    private var currentDocument: SavedDocument?
    private var playbackCursor: PlaybackCursor = PlaybackCursor()
    private var synthesisTask: Task<Void, Never>?
    private var isPlaying = false
    
    // We use a counter on the MainActor to safely track look-ahead.
    private var scheduledCount: Int = 0
    
    // The cursor currently being HEARD by the user
    var onParagraphStartedPlaying: ((PlaybackCursor) -> Void)?

    init(synthesizer: Synthesizer, player: PlayerService, lookAhead: Int = 3) {
        self.synthesizer = synthesizer
        self.player = player
        self.lookAhead = lookAhead
    }

    func start(from cursor: PlaybackCursor, in document: SavedDocument, voice: TTSVoice) {
        self.currentDocument = document
        self.playbackCursor = cursor
        self.isPlaying = true
        restartSynthesis(voice: voice)
    }

    func advanceTo(cursor: PlaybackCursor, voice: TTSVoice) {
        self.playbackCursor = cursor
        if isPlaying {
            restartSynthesis(voice: voice)
        }
    }

    func pause() {
        isPlaying = false
        synthesisTask?.cancel()
        player.pause()
    }

    func resume(voice: TTSVoice) {
        isPlaying = true
        restartSynthesis(voice: voice)
        player.play()
    }

    private func restartSynthesis(voice: TTSVoice) {
        synthesisTask?.cancel()
        player.stop()
        scheduledCount = 0
        
        synthesisTask = Task {
            await runSynthesisLoop(voice: voice)
        }
        player.play()
    }

    private func runSynthesisLoop(voice: TTSVoice) async {
        guard let doc = currentDocument else { return }
        
        var synthCursor = playbackCursor
        
        // Notify UI immediately of the start
        onParagraphStartedPlaying?(playbackCursor)
        
        while !Task.isCancelled && isPlaying {
            // Check look-ahead: don't schedule too much
            if scheduledCount >= lookAhead {
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }
            
            guard synthCursor.chapterIndex < doc.chapters.count else { break }
            let chapter = doc.chapters[synthCursor.chapterIndex]
            
            guard synthCursor.paragraphIndex < chapter.paragraphs.count else {
                synthCursor.chapterIndex += 1
                synthCursor.paragraphIndex = 0
                continue
            }
            
            let text = chapter.paragraphs[synthCursor.paragraphIndex]
            let currentLoopCursor = synthCursor
            let paragraphId = "\(currentLoopCursor.chapterIndex):\(currentLoopCursor.paragraphIndex)"
            
            let stream = synthesizer.synthesize(text, voice: voice, options: SynthOptions())
            
            do {
                var paragraphSamples = [Float]()
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    paragraphSamples.append(contentsOf: chunk.samples)
                }
                
                if Task.isCancelled { break }

                // Append ~75ms silence for a natural paragraph pause
                var paddedSamples = paragraphSamples
                paddedSamples.append(contentsOf: [Float](repeating: 0.0, count: Int(0.075 * 44100)))

                if let buffer = makePCMBuffer(from: paddedSamples) {
                    scheduledCount += 1
                    player.schedule(buffer, id: paragraphId) { [weak self] id in
                        guard let self else { return }
                        Task { @MainActor in
                            self.scheduledCount -= 1
                            self.handleParagraphFinished(id: id)
                        }
                    }
                }
            } catch {
                print("[Scheduler] Synthesis error: \(error)")
                break
            }
            
            // Advance synth cursor
            synthCursor.paragraphIndex += 1
            if synthCursor.paragraphIndex >= chapter.paragraphs.count {
                synthCursor.chapterIndex += 1
                synthCursor.paragraphIndex = 0
            }
        }
    }

    private func handleParagraphFinished(id: String) {
        guard let doc = currentDocument else { return }
        
        // Advance the cursor for what the user is hearing
        playbackCursor.paragraphIndex += 1
        if playbackCursor.paragraphIndex >= doc.chapters[playbackCursor.chapterIndex].paragraphs.count {
            playbackCursor.chapterIndex += 1
            playbackCursor.paragraphIndex = 0
        }
        
        if playbackCursor.chapterIndex < doc.chapters.count {
            onParagraphStartedPlaying?(playbackCursor)
        } else {
            isPlaying = false
        }
    }

    private func makePCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty else { return nil }

        // Peak-normalize to ~-1.4 dBFS for consistent loudness across paragraphs
        var peak: Float = 0.0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        let normalized: [Float]
        if peak > 0.001 {
            var scale = Float(0.85) / peak
            var result = [Float](repeating: 0, count: samples.count)
            vDSP_vsmul(samples, 1, &scale, &result, 1, vDSP_Length(samples.count))
            normalized = result
        } else {
            normalized = samples
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(normalized.count)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(normalized.count)
        normalized.withUnsafeBufferPointer { ptr in
            if let dest = buffer.floatChannelData?[0] {
                dest.update(from: ptr.baseAddress!, count: normalized.count)
            }
        }
        return buffer
    }
}
