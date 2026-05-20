import SwiftUI
import Combine

enum PlayerState {
    case idle
    case synthesizing
    case playing
    case paused
    case ended
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

        // Load default voice if set in UserDefaults
        let savedVoiceId = UserDefaults.standard.string(forKey: "tts.defaultVoiceId")
        if let savedVoiceId = savedVoiceId {
            let voices = scheduler is AppleVoiceScheduler 
                ? (scheduler as? AppleVoiceScheduler)?.cachedVoices ?? []
                : TTSVoice.loadAll()
            if let matched = voices.first(where: { $0.id == savedVoiceId }) {
                self.voice = matched
            }
        }

        setupCallbacks(on: scheduler)
    }

    private func setupCallbacks(on sched: any PlaybackScheduler) {
        sched.onParagraphStartedPlaying = { [weak self] cursor in
            guard let self else { return }
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
        self.voice = voice
        if state == .playing {
            scheduler.advanceTo(cursor: document.cursor, voice: voice)
        }
    }

    func switchToScheduler(_ newScheduler: any PlaybackScheduler, voices: [TTSVoice]) {
        let wasPlaying = state == .playing
        scheduler.cancelPlayback()
        player.stop()

        scheduler = newScheduler
        setupCallbacks(on: newScheduler)

        if let first = voices.first { voice = first }

        if wasPlaying {
            isBuffering = true
            newScheduler.start(from: document.cursor, in: document, voice: voice)
            player.updateNowPlaying(title: document.title, author: document.author, cover: document.coverImageData)
        }
    }
}
