import SwiftUI

@Observable
@MainActor
final class AppState {
    let libraryService:        LibraryService
    let playerService:         PlayerService
    let supertonicSynthesizer: SupertonicSynthesizer
    let synthScheduler:        SynthScheduler
    let appleVoiceScheduler:   AppleVoiceScheduler

    var selectedEngine: TTSEngine {
        didSet {
            UserDefaults.standard.set(selectedEngine.rawValue, forKey: "tts.engine")
            let newVoices: [TTSVoice] = selectedEngine == .apple
                ? appleVoiceScheduler.cachedVoices
                : TTSVoice.loadAll()
            activeSession?.switchToScheduler(activeScheduler, voices: newVoices)
        }
    }

    var activeScheduler: any PlaybackScheduler {
        selectedEngine == .apple ? appleVoiceScheduler : synthScheduler
    }

    var books: [LibraryEntry] = []
    var activeSession: ReaderSession?
    var showPlayer = false
    var selectedAppearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(selectedAppearance.rawValue, forKey: "app.appearance")
        }
    }
    var fontSize: Double {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "app.font.size")
        }
    }

    init() {
        let lib        = LibraryService()
        let player     = PlayerService()
        let supertonic = SupertonicSynthesizer()
        let apple      = AppleVoiceScheduler()
        let sched      = SynthScheduler(synthesizer: supertonic, player: player)

        let saved = UserDefaults.standard.string(forKey: "tts.engine")
            .flatMap(TTSEngine.init(rawValue:)) ?? .supertonic

        let savedAppearance = UserDefaults.standard.string(forKey: "app.appearance")
            .flatMap(AppAppearance.init(rawValue:)) ?? .system

        let savedFontSize = UserDefaults.standard.double(forKey: "app.font.size")
        let actualFontSize = savedFontSize == 0.0 ? 18.0 : savedFontSize

        libraryService        = lib
        playerService         = player
        supertonicSynthesizer = supertonic
        synthScheduler        = sched
        appleVoiceScheduler   = apple
        selectedEngine        = saved
        selectedAppearance    = savedAppearance
        fontSize              = actualFontSize

        books = lib.scanLocalLibrary()
        supertonic.checkAndPrepare()
        apple.prepareVoices()
        watchModelReadiness()

        // Route lock-screen transport through the active session
        player.onRemotePlay  = { [weak self] in self?.activeSession?.play() }
        player.onRemotePause = { [weak self] in self?.activeSession?.pause() }
        player.onRemoteSkipForward = { [weak self] interval in
            self?.activeSession?.skip(seconds: interval)
        }
        player.onRemoteSkipBackward = { [weak self] interval in
            self?.activeSession?.skip(seconds: -interval)
        }
        player.onRemoteChangePlaybackPosition = { [weak self] position in
            guard let session = self?.activeSession else { return }
            let currentElapsed = session.currentChapterElapsed
            let delta = position - currentElapsed
            session.skip(seconds: delta)
        }

        performMigration()
    }

    func refresh() {
        books = libraryService.scanLocalLibrary()
    }

    var totalHoursRead: Double {
        let totalSeconds = books.reduce(0.0) { $0 + $1.durationRead }
        return totalSeconds / 3600.0
    }

    var formattedTotalHoursRead: String {
        let hours = totalHoursRead
        if hours == 0 {
            return "0h read"
        } else if hours < 0.1 {
            let mins = Int(round(hours * 60))
            return "\(max(1, mins))m read"
        } else {
            return String(format: "%.1fh read", hours)
        }
    }

    func openDocument(_ entry: LibraryEntry) {
        if let doc = libraryService.loadDocument(id: entry.id) {
            activeSession = ReaderSession(
                document: doc,
                player: playerService,
                scheduler: activeScheduler,
                libraryService: libraryService
            )
            showPlayer = true
        }
    }

    private var isWatchingModel = false

    private func watchModelReadiness() {
        guard !isWatchingModel else { return }
        isWatchingModel = true
        withObservationTracking {
            _ = supertonicSynthesizer.modelState
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isWatchingModel = false
                if case .ready = self.supertonicSynthesizer.modelState {
                    self.selectedEngine = .supertonic
                } else {
                    self.selectedEngine = .apple
                    self.watchModelReadiness()
                }
            }
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
