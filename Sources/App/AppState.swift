import SwiftUI

@Observable
@MainActor
final class AppState {
    let libraryService:       LibraryService
    let playerService:        PlayerService
    let supertonicService:    SupertonicService
    let ttsGenerationService: TTSGenerationService
    var books: [LibraryEntry] = []

    init() {
        let lib    = LibraryService()
        let player = PlayerService()
        let sts    = SupertonicService()
        let gen    = TTSGenerationService(supertonicService: sts)
        libraryService       = lib
        playerService        = player
        supertonicService    = sts
        ttsGenerationService = gen
        books = lib.scanLocalLibrary()
        sts.checkAndPrepare()
    }

    func refresh() {
        books = libraryService.scanLocalLibrary()
    }

    func saveProgress() {
        guard let book = playerService.book else { return }
        let progress = ReadingProgress(
            chapterIdx: playerService.chapterIdx,
            time: playerService.currentTime)
        libraryService.saveProgress(progress, slug: book.slug)
    }
}
