import SwiftUI
import Combine

enum PlayerState {
    case idle
    case synthesizing
    case playing
    case paused
    case ended
}

enum SleepTimerOption: String, CaseIterable, Identifiable {
    case off = "Off"
    case m5 = "5 minutes"
    case m15 = "15 minutes"
    case m30 = "30 minutes"
    case h1 = "1 hour"
    case endOfChapter = "End of Chapter"
    
    var id: String { self.rawValue }
}

@MainActor
final class ReaderSession: ObservableObject {
    @Published var document: SavedDocument
    @Published var state: PlayerState = .idle
    @Published var isBuffering: Bool = false
    @Published var currentChapterIndex: Int
    @Published var currentParagraphIndex: Int
    @Published var playbackRate: Float = 1.0
    @Published var voice: TTSVoice = .default
    @Published var steps: Int = 4
    @Published var activeWordRange: NSRange? = nil
    
    @Published var sleepTimerOption: SleepTimerOption = .off
    @Published var sleepTimerSecondsRemaining: TimeInterval? = nil
    private var sleepTimer: Timer? = nil

    let player: PlayerService
    private(set) var scheduler: any PlaybackScheduler
    private let libraryService: LibraryService
    private var cancellables = Set<AnyCancellable>()

    init(document: SavedDocument, player: PlayerService, scheduler: any PlaybackScheduler, libraryService: LibraryService) {
        self.document = document
        self.player = player
        self.scheduler = scheduler
        self.libraryService = libraryService
        self.currentChapterIndex = document.cursor.chapterIndex
        self.currentParagraphIndex = document.cursor.paragraphIndex
        
        let savedSteps = UserDefaults.standard.integer(forKey: "tts.defaultSteps")
        self.steps = savedSteps > 0 ? savedSteps : 4

        // Setup callbacks on scheduler before playing
        setupCallbacks(on: scheduler)

        // Load default voice if set in UserDefaults, otherwise fallback
        let savedVoiceId = UserDefaults.standard.string(forKey: "tts.defaultVoiceId")
        let initialVoice = TTSVoice(
            id: savedVoiceId ?? "M1",
            name: "Default",
            language: "en",
            gender: .male
        )
        self.voice = sanitizeVoice(initialVoice, for: scheduler)
    }

    private func setupCallbacks(on sched: any PlaybackScheduler) {
        sched.onParagraphStartedPlaying = { [weak self] cursor in
            guard let self else { return }
            
            // Check End of Chapter sleep timer before updating indexes
            if self.sleepTimerOption == .endOfChapter && cursor.chapterIndex != self.currentChapterIndex {
                self.pause()
                self.setSleepTimer(.off)
                return
            }
            
            currentChapterIndex = cursor.chapterIndex
            currentParagraphIndex = cursor.paragraphIndex
            activeWordRange = nil
            document.cursor = cursor
            document.lastOpenedAt = Date()
            libraryService.saveDocument(document)
        }
        sched.onFirstAudioReady = { [weak self] in
            self?.isBuffering = false
        }
        sched.onWordRangeChanged = { [weak self] range in
            guard let self else { return }
            activeWordRange = range
        }
    }

    func play() {
        isBuffering = true
        if state == .paused {
            scheduler.resume(voice: voice)
        } else {
            scheduler.start(from: document.cursor, in: document, voice: voice)
        }
        state = .playing
        player.updateNowPlaying(title: document.title, author: document.author, cover: document.coverImageData)
    }

    func pause() {
        scheduler.pause()
        state = .paused
        isBuffering = false
    }

    func togglePlay() {
        if state == .playing {
            pause()
        } else {
            play()
        }
    }

    func skipNextParagraph() {
        var nextCursor = document.cursor
        nextCursor.paragraphIndex += 1
        if nextCursor.paragraphIndex >= document.chapters[nextCursor.chapterIndex].paragraphs.count {
            if nextCursor.chapterIndex + 1 < document.chapters.count {
                nextCursor.chapterIndex += 1
                nextCursor.paragraphIndex = 0
            } else {
                return
            }
        }
        document.cursor = nextCursor
        if state == .playing { isBuffering = true }
        scheduler.advanceTo(cursor: nextCursor, voice: voice)
        currentChapterIndex = nextCursor.chapterIndex
        currentParagraphIndex = nextCursor.paragraphIndex
    }

    func skipPrevParagraph() {
        var prevCursor = document.cursor
        prevCursor.paragraphIndex -= 1
        if prevCursor.paragraphIndex < 0 {
            if prevCursor.chapterIndex > 0 {
                prevCursor.chapterIndex -= 1
                prevCursor.paragraphIndex = document.chapters[prevCursor.chapterIndex].paragraphs.count - 1
            } else {
                prevCursor.paragraphIndex = 0
            }
        }
        document.cursor = prevCursor
        if state == .playing { isBuffering = true }
        scheduler.advanceTo(cursor: prevCursor, voice: voice)
        currentChapterIndex = prevCursor.chapterIndex
        currentParagraphIndex = prevCursor.paragraphIndex
    }

    func skip(seconds: Double) {
        let charsPerSecond = 15.0
        let charsToSeek = seconds * charsPerSecond * Double(playbackRate)
        
        let chapters = document.chapters
        guard !chapters.isEmpty else { return }
        
        // 1. Calculate current absolute character position
        var currentAbsoluteCharIndex = 0
        var foundCurrent = false
        
        for cIdx in 0..<chapters.count {
            let ch = chapters[cIdx]
            for pIdx in 0..<ch.paragraphs.count {
                if cIdx == currentChapterIndex && pIdx == currentParagraphIndex {
                    foundCurrent = true
                    break
                }
                currentAbsoluteCharIndex += ch.paragraphs[pIdx].count
            }
            if foundCurrent { break }
        }
        
        // 2. Add seeking chars
        let targetAbsoluteCharIndex = max(0, Double(currentAbsoluteCharIndex) + charsToSeek)
        
        // 3. Find the chapter and paragraph for the target absolute position
        var accumulatedChars = 0
        var targetChapterIndex = 0
        var targetParagraphIndex = 0
        var foundTarget = false
        
        for cIdx in 0..<chapters.count {
            let ch = chapters[cIdx]
            for pIdx in 0..<ch.paragraphs.count {
                let count = ch.paragraphs[pIdx].count
                if Double(accumulatedChars + count) >= targetAbsoluteCharIndex {
                    targetChapterIndex = cIdx
                    targetParagraphIndex = pIdx
                    foundTarget = true
                    break
                }
                accumulatedChars += count
            }
            if foundTarget { break }
        }
        
        // If we exceeded the total characters in the book, clamp to the very last paragraph
        if !foundTarget {
            targetChapterIndex = chapters.count - 1
            targetParagraphIndex = max(0, chapters[targetChapterIndex].paragraphs.count - 1)
        }
        
        // 4. Update cursor and advance scheduler
        let newCursor = PlaybackCursor(chapterIndex: targetChapterIndex, paragraphIndex: targetParagraphIndex)
        document.cursor = newCursor
        if state == .playing { isBuffering = true }
        scheduler.advanceTo(cursor: newCursor, voice: voice)
        currentChapterIndex = targetChapterIndex
        currentParagraphIndex = targetParagraphIndex
    }

    func jumpToChapter(_ index: Int) {
        let newCursor = PlaybackCursor(chapterIndex: index, paragraphIndex: 0)
        document.cursor = newCursor
        if state == .playing { isBuffering = true }
        scheduler.advanceTo(cursor: newCursor, voice: voice)
        currentChapterIndex = newCursor.chapterIndex
        currentParagraphIndex = newCursor.paragraphIndex
    }

    func jumpToParagraph(_ index: Int) {
        let newCursor = PlaybackCursor(chapterIndex: currentChapterIndex, paragraphIndex: index)
        document.cursor = newCursor
        if state == .playing { isBuffering = true }
        scheduler.advanceTo(cursor: newCursor, voice: voice)
        currentParagraphIndex = index
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        player.setRate(rate)   // AVAudioUnitTimePitch for Supertonic
        scheduler.setRate(rate) // utterance.rate for Apple voice
    }

    func setVoice(_ voice: TTSVoice) {
        self.voice = sanitizeVoice(voice, for: scheduler)
        if state == .playing {
            scheduler.advanceTo(cursor: document.cursor, voice: self.voice)
        }
    }

    func switchToScheduler(_ newScheduler: any PlaybackScheduler, voices: [TTSVoice]) {
        let wasPlaying = state == .playing
        scheduler.cancelPlayback()
        player.stop()

        scheduler = newScheduler
        setupCallbacks(on: newScheduler)

        self.voice = sanitizeVoice(self.voice, for: newScheduler)

        if wasPlaying {
            isBuffering = true
            newScheduler.start(from: document.cursor, in: document, voice: voice)
            player.updateNowPlaying(title: document.title, author: document.author, cover: document.coverImageData)
        }
    }

    func setSleepTimer(_ option: SleepTimerOption) {
        self.sleepTimerOption = option
        self.sleepTimer?.invalidate()
        self.sleepTimer = nil
        self.sleepTimerSecondsRemaining = nil
        
        switch option {
        case .off:
            break
        case .m5:
            startTimer(seconds: 5 * 60)
        case .m15:
            startTimer(seconds: 15 * 60)
        case .m30:
            startTimer(seconds: 30 * 60)
        case .h1:
            startTimer(seconds: 60 * 60)
        case .endOfChapter:
            break
        }
    }

    private func startTimer(seconds: TimeInterval) {
        sleepTimerSecondsRemaining = seconds
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if let remaining = self.sleepTimerSecondsRemaining {
                    if remaining <= 1 {
                        self.pause()
                        self.setSleepTimer(.off)
                    } else {
                        self.sleepTimerSecondsRemaining = remaining - 1
                    }
                }
            }
        }
    }

    private func sanitizeVoice(_ voiceToSanitize: TTSVoice, for sched: any PlaybackScheduler) -> TTSVoice {
        if sched is AppleVoiceScheduler {
            let appleVoices = (sched as? AppleVoiceScheduler)?.cachedVoices ?? []
            let available = appleVoices.isEmpty ? AppleVoiceMapper.availableVoices() : appleVoices
            
            // If the voice is already a valid Apple voice in our list, use it
            if let matched = available.first(where: { $0.id == voiceToSanitize.id }) {
                return matched
            }
            
            // If it starts with apple- but isn't in our list (maybe cachedVoices is empty but it is valid),
            // we can still use it or try to find a match in availableVoices
            if voiceToSanitize.id.hasPrefix("apple-") {
                if let matched = AppleVoiceMapper.availableVoices().first(where: { $0.id == voiceToSanitize.id }) {
                    return matched
                }
                return voiceToSanitize
            }
            
            // Otherwise, try to load default from UserDefaults if it's an Apple voice
            if let savedVoiceId = UserDefaults.standard.string(forKey: "tts.defaultVoiceId"),
               savedVoiceId.hasPrefix("apple-") {
                if let matched = AppleVoiceMapper.availableVoices().first(where: { $0.id == savedVoiceId }) {
                    return matched
                }
            }
            
            // Fallback to first available Apple voice
            if let firstApple = available.first {
                return firstApple
            }
            if let firstAvailable = AppleVoiceMapper.availableVoices().first {
                return firstAvailable
            }
            
            return voiceToSanitize
        } else {
            let supertonicVoices = TTSVoice.loadAll()
            if let matched = supertonicVoices.first(where: { $0.id == voiceToSanitize.id }) {
                return matched
            }
            
            // If not matched, try to load default from UserDefaults if it's a Supertonic voice
            if let savedVoiceId = UserDefaults.standard.string(forKey: "tts.defaultVoiceId"),
               supertonicVoices.contains(where: { $0.id == savedVoiceId }) {
                if let matched = supertonicVoices.first(where: { $0.id == savedVoiceId }) {
                    return matched
                }
            }
            
            return TTSVoice.default
        }
    }
}
