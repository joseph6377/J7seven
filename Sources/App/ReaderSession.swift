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
    @Published var currentChapterIndex: Int
    @Published var currentParagraphIndex: Int
    @Published var playbackRate: Float = 1.0
    @Published var voice: TTSVoice = .default
    @Published var steps: Int = 4

    let player: PlayerService
    let scheduler: SynthScheduler
    private let libraryService: LibraryService
    private var cancellables = Set<AnyCancellable>()

    init(document: SavedDocument, player: PlayerService, scheduler: SynthScheduler, libraryService: LibraryService) {
        self.document = document
        self.player = player
        self.scheduler = scheduler
        self.libraryService = libraryService
        self.currentChapterIndex = document.cursor.chapterIndex
        self.currentParagraphIndex = document.cursor.paragraphIndex
        
        setupCallbacks()
    }

    private func setupCallbacks() {
        scheduler.onParagraphStartedPlaying = { [weak self] cursor in
            guard let self else { return }
            self.currentChapterIndex = cursor.chapterIndex
            self.currentParagraphIndex = cursor.paragraphIndex
            
            // Persist cursor
            self.document.cursor = cursor
            self.document.lastOpenedAt = Date()
            self.libraryService.saveDocument(self.document)
        }
    }

    func play() {
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
                return // End of book
            }
        }
        document.cursor = nextCursor
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
        scheduler.advanceTo(cursor: prevCursor, voice: voice)
        currentChapterIndex = prevCursor.chapterIndex
        currentParagraphIndex = prevCursor.paragraphIndex
    }

    func jumpToChapter(_ index: Int) {
        let newCursor = PlaybackCursor(chapterIndex: index, paragraphIndex: 0)
        document.cursor = newCursor
        scheduler.advanceTo(cursor: newCursor, voice: voice)
        currentChapterIndex = newCursor.chapterIndex
        currentParagraphIndex = newCursor.paragraphIndex
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        player.setRate(rate)
    }

    func setVoice(_ voice: TTSVoice) {
        self.voice = voice
        if state == .playing {
            scheduler.advanceTo(cursor: document.cursor, voice: voice)
        }
    }
}
