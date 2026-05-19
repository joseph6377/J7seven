import SwiftUI

@Observable
@MainActor
final class AppState {
    let libraryService:       LibraryService
    let playerService:        PlayerService
    let synthesizer:          SupertonicSynthesizer
    let scheduler:            SynthScheduler
    
    var books: [LibraryEntry] = []
    var activeSession: ReaderSession?
    var showPlayer = false

    init() {
        let lib    = LibraryService()
        let player = PlayerService()
        let synth  = SupertonicSynthesizer()
        let sched  = SynthScheduler(synthesizer: synth, player: player)
        
        libraryService    = lib
        playerService     = player
        synthesizer       = synth
        scheduler         = sched
        
        books = lib.scanLocalLibrary()
        synth.checkAndPrepare()
        
        performMigration()
    }

    func refresh() {
        books = libraryService.scanLocalLibrary()
    }

    func openDocument(_ entry: LibraryEntry) {
        if let doc = libraryService.loadDocument(id: entry.id) {
            activeSession = ReaderSession(
                document: doc,
                player: playerService,
                scheduler: scheduler,
                libraryService: libraryService
            )
            showPlayer = true
        }
    }

    private func performMigration() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let oldBooks = docs.appendingPathComponent("books", isDirectory: true)
        let oldProgress = docs.appendingPathComponent("tts-progress", isDirectory: true)
        
        if FileManager.default.fileExists(atPath: oldBooks.path) {
            print("[Migration] Cleaning up old books directory...")
            try? FileManager.default.removeItem(at: oldBooks)
        }
        
        if FileManager.default.fileExists(atPath: oldProgress.path) {
            print("[Migration] Cleaning up old tts-progress directory...")
            try? FileManager.default.removeItem(at: oldProgress)
        }
    }
}
