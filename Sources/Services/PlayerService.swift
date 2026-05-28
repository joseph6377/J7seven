import AVFoundation
import MediaPlayer

@MainActor
@Observable
final class PlayerService {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let speedControl = AVAudioUnitTimePitch()

    var isPlaying: Bool = false
    private(set) var hasAudioData = false
    var playbackRate: Float = 1.0
    private var wasPlayingBeforeInterruption = false

    private let nowPlayingQueue = DispatchQueue(label: "in.josepht.BooksApp.NowPlaying")

    var onRemotePlay:                   (@MainActor () -> Void)?
    var onRemotePause:                  (@MainActor () -> Void)?
    var onRemoteSkipForward:            (@MainActor (Double) -> Void)?
    var onRemoteSkipBackward:           (@MainActor (Double) -> Void)?
    var onRemoteChangePlaybackPosition: (@MainActor (Double) -> Void)?

    init() {
        setupEngine()
        setupAudioSession()
        setupRemoteCommands()
    }

    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(speedControl)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!

        engine.connect(playerNode, to: speedControl, format: format)
        engine.connect(speedControl, to: engine.mainMixerNode, format: format)

        engine.prepare()
    }

    func schedule(_ buffer: AVAudioPCMBuffer, id: String, completion: @escaping @Sendable (String) -> Void) {
        hasAudioData = true
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: {
            Task { @MainActor in
                completion(id)
            }
        })
    }

    func play() {
        if !engine.isRunning { try? engine.start() }
        playerNode.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
        hasAudioData = false
        updateNowPlaying()
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        speedControl.rate = rate
        updateNowPlaying()
    }

    // MARK: - Audio session

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
            print("[Player] Audio session active: category=\(session.category.rawValue)")

            NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { [weak self] notification in
                guard let userInfo = notification.userInfo,
                      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

                let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt

                Task { @MainActor in
                    self?.handleInterruption(type: type, optionsValue: optionsValue)
                }
            }
        } catch {
            print("[Player] Audio session setup failed: \(error)")
        }
    }

    private func handleInterruption(type: AVAudioSession.InterruptionType, optionsValue: UInt?) {
        if type == .began {
            wasPlayingBeforeInterruption = isPlaying
            pause()
        } else if type == .ended {
            if wasPlayingBeforeInterruption, let optionsValue = optionsValue {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    play()
                }
            }
            wasPlayingBeforeInterruption = false
        }
    }

    // MARK: - Remote Commands & Now Playing

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if let handler = self?.onRemotePlay { handler() } else { self?.play() }
            }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if let handler = self?.onRemotePause { handler() } else { self?.pause() }
            }
            return .success
        }

        c.skipForwardCommand.preferredIntervals = [15]
        c.skipForwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            let interval = skipEvent.interval
            Task { @MainActor in
                self?.onRemoteSkipForward?(interval)
            }
            return .success
        }

        c.skipBackwardCommand.preferredIntervals = [15]
        c.skipBackwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            let interval = skipEvent.interval
            Task { @MainActor in
                self?.onRemoteSkipBackward?(interval)
            }
            return .success
        }

        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = positionEvent.positionTime
            Task { @MainActor in
                self?.onRemoteChangePlaybackPosition?(position)
            }
            return .success
        }
    }

    func updateNowPlaying(
        isPlaying: Bool? = nil,
        title: String? = nil,
        author: String? = nil,
        cover: Data? = nil,
        duration: Double? = nil,
        elapsedTime: Double? = nil
    ) {
        let playing = isPlaying ?? self.isPlaying
        let rate = self.playbackRate

        nowPlayingQueue.async {
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            if let title { info[MPMediaItemPropertyTitle] = title }
            if let author { info[MPMediaItemPropertyArtist] = author }
            if let cover, let image = UIImage(data: cover) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
            if let duration {
                info[MPMediaItemPropertyPlaybackDuration] = duration
            }
            if let elapsedTime {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
            }
            info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? Double(rate) : 0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info

            MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
        }
    }
}
