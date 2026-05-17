import SwiftUI

@Observable
final class AppState {
    let libraryService   = LibraryService()
    let playerService    = PlayerService()
    let supertonicService = SupertonicService()
    lazy var ttsGenerationService = TTSGenerationService(supertonicService: supertonicService)

    var books: [LibraryEntry] = []

    init() {
        refresh()
    }

    func refresh() {
        books = libraryService.scanLocalLibrary()
    }
}
