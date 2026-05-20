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

    private let nowPlayingQueue = DispatchQueue(label: "in.josepht.BooksApp.NowPlaying")

    var onRemotePlay:  (@MainActor () -> Void)?
    var onRemotePause: (@MainActor () -> Void)?

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
            pause()
        } else if type == .ended {
            if let optionsValue = optionsValue {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    play()
                }
            }
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
    }

    func updateNowPlaying(title: String? = nil, author: String? = nil, cover: Data? = nil) {
        let isPlaying = self.isPlaying
        let rate = self.playbackRate
        
        nowPlayingQueue.async {
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            if let title { info[MPMediaItemPropertyTitle] = title }
            if let author { info[MPMediaItemPropertyArtist] = author }
            if let cover, let image = UIImage(data: cover) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
            info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}
