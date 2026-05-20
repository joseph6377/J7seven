@preconcurrency import AVFoundation
import Foundation

@Observable
@MainActor
final class AppleVoiceScheduler: NSObject, PlaybackScheduler {

    // MARK: - Voice discovery (for settings UI)

    private(set) var cachedVoices: [TTSVoice] = []
    private(set) var hasPremiumVoice: Bool = false

    // MARK: - PlaybackScheduler

    var onParagraphStartedPlaying: ((PlaybackCursor) -> Void)?
    var onFirstAudioReady: (() -> Void)?
    var onWordRangeChanged: ((NSRange) -> Void)?

    // MARK: - Private state

    private let synth = AVSpeechSynthesizer()
    private var currentDocument: SavedDocument?
    private var currentVoice: TTSVoice = .default
    private var currentRate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var playbackCursor = PlaybackCursor()
    private var synthCursor = PlaybackCursor()
    private var scheduledCount = 0
    private var isPlaying = false
    private(set) var isWaitingForFirstUtterance = false
    private let lookAhead = 3

    // Maps ObjectIdentifier(utterance) → PlaybackCursor
    private var utteranceCursorMap: [ObjectIdentifier: PlaybackCursor] = [:]
    private var currentUtteranceId: ObjectIdentifier? = nil

    override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: - Voice preparation

    func prepareVoices() {
        Task {
            let voices: [TTSVoice] = await Task.detached(priority: .utility) {
                AppleVoiceMapper.availableVoices()
            }.value
            let premium: Bool = await Task.detached(priority: .utility) {
                AppleVoiceMapper.hasPremiumVoice()
            }.value
            self.cachedVoices = voices
            self.hasPremiumVoice = premium
        }
    }

    // MARK: - PlaybackScheduler

    func start(from cursor: PlaybackCursor, in document: SavedDocument, voice: TTSVoice) {
        currentDocument = document
        currentVoice = voice
        playbackCursor = cursor
        synthCursor = cursor
        isPlaying = true
        isWaitingForFirstUtterance = true
        stopAndClearQueue()
        onParagraphStartedPlaying?(cursor)
        enqueueNextParagraphs()
    }

    func advanceTo(cursor: PlaybackCursor, voice: TTSVoice) {
        currentVoice = voice
        playbackCursor = cursor
        synthCursor = cursor
        stopAndClearQueue()
        if isPlaying {
            isWaitingForFirstUtterance = true
            onParagraphStartedPlaying?(cursor)
            enqueueNextParagraphs()
        }
    }

    func pause() {
        isPlaying = false
        isWaitingForFirstUtterance = false
        synth.pauseSpeaking(at: .immediate)
    }

    func resume(voice: TTSVoice) {
        currentVoice = voice
        isPlaying = true
        if synth.continueSpeaking() {
            onFirstAudioReady?()
        } else {
            isWaitingForFirstUtterance = true
            enqueueNextParagraphs()
        }
    }

    func cancelPlayback() {
        isPlaying = false
        isWaitingForFirstUtterance = false
        stopAndClearQueue()
    }

    func setRate(_ rate: Float) {
        currentRate = Self.utteranceRate(for: rate)
        if isPlaying {
            advanceTo(cursor: playbackCursor, voice: currentVoice)
        }
    }

    // MARK: - Private helpers

    private func stopAndClearQueue() {
        synth.stopSpeaking(at: .immediate)
        utteranceCursorMap.removeAll()
        currentUtteranceId = nil
        scheduledCount = 0
    }

    private func enqueueNextParagraphs() {
        guard let doc = currentDocument else { return }
        let avVoice = AppleVoiceMapper.avVoice(for: currentVoice)
        let rate = currentRate

        while scheduledCount < lookAhead {
            guard synthCursor.chapterIndex < doc.chapters.count else { break }
            let chapter = doc.chapters[synthCursor.chapterIndex]

            guard synthCursor.paragraphIndex < chapter.paragraphs.count else {
                synthCursor.chapterIndex += 1
                synthCursor.paragraphIndex = 0
                continue
            }

            let text = chapter.paragraphs[synthCursor.paragraphIndex]
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = avVoice
            utterance.rate = rate

            utteranceCursorMap[ObjectIdentifier(utterance)] = synthCursor
            synth.speak(utterance)
            scheduledCount += 1

            synthCursor.paragraphIndex += 1
            if synthCursor.paragraphIndex >= chapter.paragraphs.count {
                synthCursor.chapterIndex += 1
                synthCursor.paragraphIndex = 0
            }
        }
    }

    // Maps the player speed picker (0.8–2.0) to AVSpeechUtterance rate (0.0–1.0).
    // Anchors at 1.0x → default rate (0.5) for a natural baseline.
    private static func utteranceRate(for playerRate: Float) -> Float {
        let base = AVSpeechUtteranceDefaultSpeechRate
        let rate = playerRate <= 1.0
            ? base * playerRate
            : base + (playerRate - 1.0) * 0.25
        return max(AVSpeechUtteranceMinimumSpeechRate,
                   min(AVSpeechUtteranceMaximumSpeechRate, rate))
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AppleVoiceScheduler: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentUtteranceId = id
            if isWaitingForFirstUtterance {
                isWaitingForFirstUtterance = false
                onFirstAudioReady?()
            }
            if let cursor = utteranceCursorMap[id] {
                playbackCursor = cursor
                onParagraphStartedPlaying?(cursor)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self else { return }
            utteranceCursorMap.removeValue(forKey: id)
            scheduledCount = max(0, scheduledCount - 1)
            if isPlaying {
                enqueueNextParagraphs()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.utteranceCursorMap.removeValue(forKey: id)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOf characterRange: NSRange, utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard self.currentUtteranceId == id else { return }
            self.onWordRangeChanged?(characterRange)
        }
    }
}
