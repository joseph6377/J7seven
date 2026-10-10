import AVFoundation
@preconcurrency import MediaPlayer
import UIKit

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

    var onRemotePlay:                   (@MainActor () -> Void)?
    var onRemotePause:                  (@MainActor () -> Void)?
    var onRemoteSkipForward:            (@MainActor (Double) -> Void)?
    var onRemoteSkipBackward:           (@MainActor (Double) -> Void)?
    var onRemoteChangePlaybackPosition: (@MainActor (Double) -> Void)?

    init() {
        setupEngine()
        setupAudioSession()
        setupRemoteCommands(commandCenter: MPRemoteCommandCenter.shared())
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
        
        // If the player is in the playing state but playerNode has run dry/stopped
        // (e.g., lookahead synthesis took a moment), automatically restart playerNode to resume seamless playback
        if isPlaying && !playerNode.isPlaying {
            if !engine.isRunning {
                do {
                    try engine.start()
                } catch {
                    print("[Player] Audio engine failed to resume in schedule: \(error)")
                }
            }
            if engine.isRunning {
                playerNode.play()
            }
        }
    }

    func play() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[Player] Audio session activation failed: \(error)")
        }

        if !engine.isRunning {
            do {
                try engine.start()
                print("[Player] Audio engine started in play()")
            } catch {
                print("[Player] Audio engine failed to start in play(): \(error)")
            }
        }
        
        guard engine.isRunning else {
            print("[Player] Cannot play - audio engine is not running and failed to start.")
            return
        }
        
        playerNode.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        playerNode.pause()
        engine.pause() // Ensure hardware I/O pauses alongside the node
        isPlaying = false
        updateNowPlaying()
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        isPlaying = false
        hasAudioData = false

        nowPlayingInfoCenter.nowPlayingInfo = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[Player] Audio session deactivation failed: \(error)")
        }
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
            print("[Player] Audio session category set: \(session.category.rawValue)")

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

    private func setupRemoteCommands(commandCenter c: MPRemoteCommandCenter) {
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

        let infoCenter = nowPlayingInfoCenter
        var info = infoCenter.nowPlayingInfo ?? [:]
        if let title { info[MPMediaItemPropertyTitle] = title }
        if let author { info[MPMediaItemPropertyArtist] = author }
        if let cover, let artwork = Self.makeArtwork(from: cover) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let elapsedTime {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        }

        // Drives the Lock Screen scrubber and the CarPlay elapsed-time extrapolation.
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? Double(rate) : 0.0

        infoCenter.nowPlayingInfo = info

        // CarPlay's Now Playing template draws its play/pause glyph from `playbackState`
        // (an explicit enum), NOT from the inferred playback rate — without this the
        // CarPlay button stays stale (shows Play while audio plays) even though the
        // scrubber advances correctly. This is public API for the app's OWN now-playing
        // info and needs no entitlement (`com.apple.mediaremote.set-playback-state` is
        // only for controlling *other* apps, which we never do).
        infoCenter.playbackState = playing ? .playing : .paused
    }

    // NOTE: The historical iOS 26 "MPNowPlayingInfoCenter crash" was NOT in the default
    // center itself — it was the actor-isolated artwork handler (see makeArtwork below).
    // The MPNowPlayingSession(players: [dummyPlayer]) workaround has been removed because
    // a session bound to a never-playing AVPlayer makes CarPlay report a paused state
    // regardless of the published playback rate.
    private var nowPlayingInfoCenter: MPNowPlayingInfoCenter {
        MPNowPlayingInfoCenter.default()
    }

    // MediaPlayer invokes the artwork handler lazily on its own internal queue. The
    // handler must therefore carry NO actor isolation: an inline closure formed in a
    // @MainActor method gets stamped @MainActor, and the runtime isolation check traps
    // (_dispatch_assert_queue_fail) inside -[MPMediaItemArtwork jpegDataWithSize:] on
    // iOS 26. Building it in a nonisolated context keeps the handler isolation-free.
    nonisolated private static func makeArtwork(from data: Data) -> MPMediaItemArtwork? {
        guard let image = UIImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
