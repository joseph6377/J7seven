import AVFoundation
import MediaPlayer
import Combine

@MainActor
@Observable
final class PlayerService {
    // MARK: - Playback state
    var book: BookManifest?
    var chapterIdx: Int = 0
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying: Bool = false
    var playbackRate: Float = 1.0
    var currentParagraphId: String? = nil
    var currentWordIdx: Int? = nil
    // Fraction (0...1) of how far playback is into the active paragraph.
    // Used by the reader as a fallback when the manifest has no word-level timing.
    var currentParagraphProgress: Double = 0

    // MARK: - Sleep timer
    var sleepEndTime: Date? = nil

    private let player = AVPlayer()
    nonisolated(unsafe) private var timeObserver: Any?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    private var sleepTask: Task<Void, Never>?

    init() {
        setupAudioSession()
        setupRemoteCommands()
    }

    // MARK: - Public API

    func play(book: BookManifest, chapterIdx: Int = 0, time: Double = 0) {
        self.book = book
        loadChapter(idx: chapterIdx, startTime: time, shouldPlay: true)
    }

    func resume() {
        player.play()
        player.rate = playbackRate
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlay() {
        isPlaying ? pause() : resume()
    }

    func skip(seconds: Double) {
        let target = max(0, min(duration, currentTime + seconds))
        seek(to: target)
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        syncMetadata(to: time)
        updateNowPlaying()
    }

    private func syncMetadata(to time: Double) {
        guard let book, chapterIdx < book.chapters.count else { return }
        let ch = book.chapters[chapterIdx]
        let para = ch.paragraphs.first(where: { time >= $0.start && time < $0.end })

        if para?.id != currentParagraphId {
            currentParagraphId = para?.id
            currentWordIdx = nil
            currentParagraphProgress = 0
        }

        if let para {
            let timeInPara = time - para.start
            let span = para.end - para.start
            currentParagraphProgress = span > 0 ? min(1, max(0, timeInPara / span)) : 0

            if para.wordEnds.isEmpty {
                // No word-level timing in the manifest — let the renderer interpolate
                // from currentParagraphProgress.
                if currentWordIdx != nil { currentWordIdx = nil }
            } else {
                let idx = para.wordEnds.firstIndex(where: { $0 > timeInPara }) ?? max(0, para.wordEnds.count - 1)
                if currentWordIdx != idx { currentWordIdx = idx }
            }
        } else {
            currentParagraphId = nil
            currentWordIdx = nil
            currentParagraphProgress = 0
        }
    }

    func nextChapter() {
        guard let book else { return }
        if chapterIdx + 1 < book.chapters.count {
            loadChapter(idx: chapterIdx + 1, startTime: 0, shouldPlay: isPlaying)
        }
    }

    func prevChapter() {
        if currentTime > 3 {
            seek(to: 0)
        } else if chapterIdx > 0 {
            loadChapter(idx: chapterIdx - 1, startTime: 0, shouldPlay: isPlaying)
        }
    }

    func setSpeed(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player.rate = rate }
        updateNowPlaying()
    }

    // MARK: - Sleep timer

    func setSleep(minutes: Double?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepEndTime = nil
        guard let minutes else { return }
        let end = Date.now.addingTimeInterval(minutes * 60)
        sleepEndTime = end
        sleepTask = Task { @MainActor in
            try? await Task.sleep(until: .now + .seconds(minutes * 60), clock: .continuous)
            if !Task.isCancelled { self.pause() ; self.sleepEndTime = nil }
        }
    }

    // MARK: - Chapter loading

    func loadChapter(idx: Int, startTime: Double, shouldPlay: Bool) {
        guard let book else { return }
        chapterIdx = idx
        currentParagraphId = nil
        currentWordIdx = nil

        let slug = book.slug
        let ch   = book.chapters[idx]
        let url  = BookPaths.localURL(slug: slug, filename: ch.audio)

        removeObservers()

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.onTimeUpdate(time.seconds)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.onChapterEnded()
        }

        if startTime > 0 {
            let cmTime = CMTime(seconds: startTime, preferredTimescale: 600)
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        if shouldPlay {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        } else {
            isPlaying = false
        }

        updateNowPlayingMeta()
    }

    // MARK: - Time update

    private func onTimeUpdate(_ time: Double) {
        currentTime = time
        duration = player.currentItem?.duration.seconds ?? 0
        syncMetadata(to: time)

        // Sleep timer tick check
        if let end = sleepEndTime, Date.now >= end {
            pause()
            sleepEndTime = nil
        }

        updateNowPlayingTime()
    }

    private func onChapterEnded() {
        guard let book else { return }
        if chapterIdx + 1 < book.chapters.count {
            loadChapter(idx: chapterIdx + 1, startTime: 0, shouldPlay: true)
        } else {
            isPlaying = false
        }
    }

    // MARK: - Audio session

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio, options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("Audio session error: \(error)") }
    }

    // MARK: - Now Playing + Remote Commands

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()

        c.playCommand.addTarget  { [weak self] _ in DispatchQueue.main.async { self?.resume() };        return .success }
        c.pauseCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.pause() };         return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.togglePlay() }; return .success }
        c.nextTrackCommand.addTarget     { [weak self] _ in DispatchQueue.main.async { self?.nextChapter() };  return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.prevChapter() };  return .success }
        c.skipForwardCommand.preferredIntervals  = [30]
        c.skipBackwardCommand.preferredIntervals = [30]
        c.skipForwardCommand.addTarget  { [weak self] _ in DispatchQueue.main.async { self?.skip(seconds: 30) };  return .success }
        c.skipBackwardCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.skip(seconds: -30) }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            DispatchQueue.main.async { self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private nonisolated static func makeArtwork(_ img: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: img.size) { _ in img }
    }

    private func updateNowPlayingMeta() {
        guard let book, chapterIdx < book.chapters.count else { return }
        let ch = book.chapters[chapterIdx]
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:           ch.title,
            MPMediaItemPropertyArtist:          book.author,
            MPMediaItemPropertyAlbumTitle:      book.title,
            MPMediaItemPropertyMediaType:       MPMediaType.anyAudio.rawValue,
            MPNowPlayingInfoPropertyMediaType:  MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        if let coverFile = book.cover {
            let url = BookPaths.localURL(slug: book.slug, filename: coverFile)
            if let img = UIImage(contentsOfFile: url.path) {
                info[MPMediaItemPropertyArtwork] = Self.makeArtwork(img)
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateNowPlayingTime()
    }

    private func updateNowPlayingTime() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration]         = duration
        info[MPNowPlayingInfoPropertyPlaybackRate]        = isPlaying ? Double(playbackRate) : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlaying() {
        updateNowPlayingTime()
    }

    // MARK: - Cleanup

    @MainActor
    private func removeObservers() {
        if let obs = timeObserver { player.removeTimeObserver(obs); timeObserver = nil }
        if let obs = endObserver  { NotificationCenter.default.removeObserver(obs); endObserver = nil }
    }

    deinit {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        if let obs = endObserver  { NotificationCenter.default.removeObserver(obs) }
    }
}
