import Foundation
import AVFoundation
import Accelerate

@MainActor
protocol PlaybackScheduler: AnyObject {
    var onParagraphStartedPlaying: ((PlaybackCursor) -> Void)? { get set }
    var onFirstAudioReady: (() -> Void)? { get set }
    var onWordRangeChanged: ((NSRange) -> Void)? { get set }
    var onPlaybackError: ((any Error) -> Void)? { get set }
    func start(from cursor: PlaybackCursor, in document: SavedDocument, voice: TTSVoice)
    func advanceTo(cursor: PlaybackCursor, voice: TTSVoice)
    func pause()
    func resume(voice: TTSVoice)
    func cancelPlayback()
    func setRate(_ rate: Float)
}

extension PlaybackScheduler {
    func setRate(_ rate: Float) {}
}

@MainActor
final class SynthScheduler: PlaybackScheduler {
    private let synthesizer: any Synthesizer
    private let player: PlayerService
    private let lookAhead: Int

    private var currentDocument: SavedDocument?
    private var playbackCursor: PlaybackCursor = PlaybackCursor()
    private var lastNotifiedParagraphCursor: PlaybackCursor?
    private var synthesisTask: Task<Void, Never>?
    private var isPlaying = false

    private var scheduledCount: Int = 0
    private var firstAudioFired = false

    var steps: Int = 8

    var onParagraphStartedPlaying: ((PlaybackCursor) -> Void)?
    var onFirstAudioReady: (() -> Void)?
    var onWordRangeChanged: ((NSRange) -> Void)?
    var onPlaybackError: ((any Error) -> Void)?
    private var wordHighlightTask: Task<Void, Never>?
    
    private var playbackSessionId = 0
    
    private struct ScheduledSentence: Sendable {
        let id: String
        let text: String
        let range: NSRange
        let duration: Double
        let chapterIndex: Int
        let paragraphIndex: Int
        let sentenceIndex: Int
    }
    
    private var scheduledQueue: [ScheduledSentence] = []
    private var sentenceDurations: [String: Double] = [:]

    init(synthesizer: any Synthesizer, player: PlayerService, lookAhead: Int = 2) {
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
        wordHighlightTask?.cancel()
        player.pause()
    }

    func resume(voice: TTSVoice) {
        isPlaying = true
        restartSynthesis(voice: voice)
        player.play()
    }

    func cancelPlayback() {
        isPlaying = false
        synthesisTask?.cancel()
        wordHighlightTask?.cancel()
        synthesizer.cancelAll()
        player.stop()
        scheduledCount = 0
        scheduledQueue.removeAll()
    }

    private func restartSynthesis(voice: TTSVoice) {
        synthesisTask?.cancel()
        wordHighlightTask?.cancel()
        synthesizer.cancelAll()
        player.stop()
        scheduledCount = 0
        firstAudioFired = false
        
        playbackSessionId += 1
        scheduledQueue.removeAll()
        lastNotifiedParagraphCursor = nil

        synthesisTask = Task {
            await runSynthesisLoop(voice: voice)
        }
        player.play()
    }

    private func getSentencesAndRanges(from paragraphText: String) -> [(text: String, range: NSRange)] {
        let sentenceStrings = chunkText(paragraphText)
        var results: [(text: String, range: NSRange)] = []
        var searchStartIndex = paragraphText.startIndex
        
        for sentence in sentenceStrings {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            if let range = paragraphText.range(of: trimmed, range: searchStartIndex..<paragraphText.endIndex) {
                let nsRange = NSRange(range, in: paragraphText)
                results.append((trimmed, nsRange))
                searchStartIndex = range.upperBound
            } else {
                if let range = paragraphText.range(of: trimmed) {
                    let nsRange = NSRange(range, in: paragraphText)
                    results.append((trimmed, nsRange))
                }
            }
        }
        return results
    }

    private func runSynthesisLoop(voice: TTSVoice) async {
        guard let doc = currentDocument else { return }

        var synthCursor = playbackCursor

        while !Task.isCancelled && isPlaying {
            // High sentence lookahead to ensure seamless playback (usually 6 sentences)
            if scheduledCount >= 6 {
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

            let text = chapter.paragraphs[synthCursor.paragraphIndex].text
            let currentLoopCursor = synthCursor

            let sentences = getSentencesAndRanges(from: text)
            let finalSentences = sentences.isEmpty ? [(text, NSRange(location: 0, length: text.utf16.count))] : sentences

            let stream = synthesizer.synthesize(text, voice: voice, options: SynthOptions(steps: steps))

            do {
                var sentenceIdx = 0
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    let sentenceText: String
                    let sentenceRange: NSRange
                    
                    if sentenceIdx < finalSentences.count {
                        sentenceText = finalSentences[sentenceIdx].text
                        sentenceRange = finalSentences[sentenceIdx].range
                    } else {
                        sentenceText = ""
                        sentenceRange = NSRange(location: 0, length: 0)
                    }
                    
                    let sentenceId = "\(currentLoopCursor.chapterIndex):\(currentLoopCursor.paragraphIndex):\(sentenceIdx)"
                    
                    // Pad with a tiny bit of silence (0.05s) to guarantee high quality, click-free crossfades between sentences
                    var paddedSamples = chunk.samples
                    paddedSamples.append(contentsOf: [Float](repeating: 0.0, count: Int(0.05 * 44100)))

                    if let buffer = makePCMBuffer(from: paddedSamples) {
                        let duration = Double(paddedSamples.count) / 44100.0
                        sentenceDurations[sentenceId] = duration
                        
                        let schedSentence = ScheduledSentence(
                            id: sentenceId,
                            text: sentenceText,
                            range: sentenceRange,
                            duration: duration,
                            chapterIndex: currentLoopCursor.chapterIndex,
                            paragraphIndex: currentLoopCursor.paragraphIndex,
                            sentenceIndex: sentenceIdx
                        )
                        
                        let currentSession = self.playbackSessionId
                        scheduledCount += 1
                        
                        let isFirst = !firstAudioFired
                        if !firstAudioFired {
                            firstAudioFired = true
                            onFirstAudioReady?()
                        }
                        
                        scheduledQueue.append(schedSentence)
                        
                        player.schedule(buffer, id: sentenceId) { [weak self] completedId in
                            guard let self else { return }
                            Task { @MainActor in
                                self.scheduledCount = max(0, self.scheduledCount - 1)
                                self.handleSentenceFinished(id: completedId, sessionId: currentSession)
                            }
                        }
                        
                        if isFirst {
                            setActiveSentence(schedSentence)
                        }
                    }
                    
                    sentenceIdx += 1
                }
            } catch is CancellationError {
                break
            } catch {
                print("[Scheduler] Synthesis error: \(error)")
                self.onPlaybackError?(error)
                self.cancelPlayback()
                break
            }

            synthCursor.paragraphIndex += 1
            if synthCursor.paragraphIndex >= chapter.paragraphs.count {
                synthCursor.chapterIndex += 1
                synthCursor.paragraphIndex = 0
            }
        }
    }

    private func handleSentenceFinished(id: String, sessionId: Int) {
        guard isPlaying, sessionId == playbackSessionId else { return }
        
        if !scheduledQueue.isEmpty && scheduledQueue[0].id == id {
            scheduledQueue.removeFirst()
        }
        
        if let nextSentence = scheduledQueue.first {
            setActiveSentence(nextSentence)
        } else {
            guard let doc = currentDocument else { return }
            let lastCursor = playbackCursor
            let lastChapter = doc.chapters.last
            let lastParaIndex = (lastChapter?.paragraphs.count ?? 1) - 1
            if lastCursor.chapterIndex >= doc.chapters.count - 1 && lastCursor.paragraphIndex >= lastParaIndex {
                isPlaying = false
                wordHighlightTask?.cancel()
                onWordRangeChanged?(.init(location: 0, length: 0))
            }
        }
    }

    private func setActiveSentence(_ sentence: ScheduledSentence) {
        playbackCursor = PlaybackCursor(chapterIndex: sentence.chapterIndex, paragraphIndex: sentence.paragraphIndex)
        
        // Heavy disk writes and scroll updates are throttled so they only fire on true paragraph transitions
        if lastNotifiedParagraphCursor?.chapterIndex != sentence.chapterIndex ||
           lastNotifiedParagraphCursor?.paragraphIndex != sentence.paragraphIndex {
            lastNotifiedParagraphCursor = playbackCursor
            onParagraphStartedPlaying?(playbackCursor)
        }
        
        startWordHighlighting(
            for: sentence.text,
            sentenceRangeInParagraph: sentence.range,
            duration: sentence.duration
        )
    }

    private func startWordHighlighting(for sentenceText: String, sentenceRangeInParagraph: NSRange, duration: Double) {
        wordHighlightTask?.cancel()
        
        var words: [(range: NSRange, text: String)] = []
        sentenceText.enumerateSubstrings(in: sentenceText.startIndex..<sentenceText.endIndex, options: .byWords) { substring, substringRange, _, _ in
            if let substring = substring {
                let nsRange = NSRange(substringRange, in: sentenceText)
                words.append((nsRange, substring))
            }
        }
        
        guard !words.isEmpty else {
            onWordRangeChanged?(sentenceRangeInParagraph)
            return
        }
        
        let totalChars = words.reduce(0) { $0 + $1.text.count }
        guard totalChars > 0 else { return }
        
        var wordTimings: [(range: NSRange, startTime: Double, endTime: Double)] = []
        var currentStart = 0.0
        for word in words {
            let wordWeight = Double(word.text.count) / Double(totalChars)
            let wordDuration = wordWeight * duration
            let paragraphWordRange = NSRange(
                location: sentenceRangeInParagraph.location + word.range.location,
                length: word.range.length
            )
            wordTimings.append((paragraphWordRange, currentStart, currentStart + wordDuration))
            currentStart += wordDuration
        }
        
        let startTime = Date()
        
        wordHighlightTask = Task { [weak self] in
            var accumulatedElapsed: Double = 0.0
            var lastTickTime = Date()
            
            while !Task.isCancelled {
                guard let self = self else { return }
                
                if !self.isPlaying {
                    try? await Task.sleep(for: .milliseconds(30))
                    lastTickTime = Date()
                    continue
                }
                
                let now = Date()
                let tickDuration = now.timeIntervalSince(lastTickTime)
                lastTickTime = now
                
                accumulatedElapsed += tickDuration * Double(self.player.playbackRate)
                
                if accumulatedElapsed >= duration {
                    break
                }
                
                if let active = wordTimings.first(where: { accumulatedElapsed >= $0.startTime && accumulatedElapsed < $0.endTime }) {
                    self.onWordRangeChanged?(active.range)
                }
                
                try? await Task.sleep(for: .milliseconds(15))
            }
        }
    }

    private func makePCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty else { return nil }

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
