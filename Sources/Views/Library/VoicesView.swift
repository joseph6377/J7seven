import SwiftUI
import AVFoundation
import Accelerate

struct VoicesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var samplePlayer = VoiceSamplePlayer()
    @State private var showModelDownload = false

    private var supertonicVoices: [TTSVoice] { TTSVoice.loadAll() }
    private var appleVoices: [TTSVoice] { appState.appleVoiceScheduler.cachedVoices }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Header Studio Description Card (2026 Editorial touch)
                    narratorIntroCard
                        .padding(.horizontal, 16)
                    
                    // Supertonic AI Voices Section
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Narrator Studio")
                                    .font(.system(.title3, design: .serif).bold())
                                Text("Premium custom-trained models")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("AI On-Device")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        .padding(.horizontal, 16)
                        
                        LazyVStack(spacing: 12) {
                            ForEach(supertonicVoices) { voice in
                                AcousticVoiceCard(
                                    voice: voice,
                                    isActive: isVoiceActive(voice),
                                    isPlaying: samplePlayer.playingVoiceId == voice.id,
                                    isPremium: true,
                                    description: description(for: voice),
                                    onPlayToggle: {
                                        playPreview(for: voice)
                                    },
                                    onSelect: {
                                        selectVoice(voice)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Apple System Voices Section
                    if !appleVoices.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("System Classics")
                                    .font(.system(.title3, design: .serif).bold())
                                Text("Native system synthesizers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            
                            LazyVStack(spacing: 12) {
                                ForEach(appleVoices) { voice in
                                    AcousticVoiceCard(
                                        voice: voice,
                                        isActive: isVoiceActive(voice),
                                        isPlaying: samplePlayer.playingVoiceId == voice.id,
                                        isPremium: false,
                                        description: description(for: voice),
                                        onPlayToggle: {
                                            playPreview(for: voice)
                                        },
                                        onSelect: {
                                            selectVoice(voice)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 120) // Cushion for floating bottom player deck
            }
            .navigationTitle("Voices")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear {
                samplePlayer.stop()
            }
            .sheet(isPresented: $showModelDownload) {
                ModelDownloadView(
                    synthesizer: appState.supertonicSynthesizer,
                    onReady: {}
                )
                .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
        }
    }

    // MARK: - Subviews

    private var narratorIntroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.badge.mic")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Supertonic 3 Narration Engine")
                        .font(.system(.subheadline, design: .serif).bold())
                    Text("Offline Synthesis • Neural Engine")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            Text("Experience fully private, studio-quality audiobook narration. Each model is custom-trained to provide unique natural inflection, deep characterization, and high-fidelity vocal textures, synthesized dynamically on your Apple Neural Engine.")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding(.all, 16)
        .background(Color.accentColor.opacity(0.02))
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Helper Methods

    private func isVoiceActive(_ voice: TTSVoice) -> Bool {
        if let activeSession = appState.activeSession {
            return activeSession.voice.id == voice.id
        } else {
            let savedVoiceId = UserDefaults.standard.string(forKey: "tts.defaultVoiceId") ?? "M1"
            return voice.id == savedVoiceId
        }
    }

    private func selectVoice(_ voice: TTSVoice) {
        // Automatically synchronize active engine with selected voice type
        let isApple = voice.id.hasPrefix("apple-")
        appState.selectedEngine = isApple ? .apple : .supertonic

        if let activeSession = appState.activeSession {
            activeSession.setVoice(voice)
        }
        UserDefaults.standard.set(voice.id, forKey: "tts.defaultVoiceId")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func playPreview(for voice: TTSVoice) {
        if !voice.id.hasPrefix("apple-") && !isSupertonicReady() {
            showModelDownload = true
        } else {
            samplePlayer.playSample(
                for: voice,
                synthesizer: appState.supertonicSynthesizer,
                activeSession: appState.activeSession
            )
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func isSupertonicReady() -> Bool {
        if case .ready = appState.supertonicSynthesizer.modelState {
            return true
        }
        return false
    }

    private func description(for voice: TTSVoice) -> String {
        switch voice.id {
        case "M1": return "Deep, Cinematic & Resonant"
        case "M2": return "Clear, Articulate & Professional"
        case "M3": return "Warm, Engaging & Conversational"
        case "M4": return "Energetic, Crisp & Dramatic"
        case "M5": return "Smooth, Classic & Expressive"
        case "F1": return "Sleek, Vibrant & Narrative"
        case "F2": return "Warm, Comforting & Gentle"
        case "F3": return "Crisp, Articulate & Educational"
        case "F4": return "Bright, Lively & Animated"
        case "F5": return "Soft, Elegant & Whispering"
        default:
            return voice.gender == .male ? "Standard Male voice preview" : "Standard Female voice preview"
        }
    }
}

// MARK: - Acoustic Card Component

struct AcousticVoiceCard: View {
    let voice: TTSVoice
    let isActive: Bool
    let isPlaying: Bool
    let isPremium: Bool
    let description: String
    let onPlayToggle: () -> Void
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Fluid Spherical Avatar
                FluidAvatarView(voice: voice)
                    .frame(width: 52, height: 52)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(voice.name)
                            .font(.system(.headline, design: .serif))
                            .foregroundStyle(isActive ? Color.accentColor : .primary)
                        
                        if isPremium {
                            Text("STUDIO AI")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        } else {
                            Text("SYSTEM")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        
                        if isActive {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    
                    Text(description)
                        .font(.system(.subheadline, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(voice.gender == .male ? "Male" : "Female")
                        Text("•")
                        Text(voice.language == "en" ? "English" : voice.language.uppercased())
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                // Visualizer & play preview block
                HStack(spacing: 12) {
                    if isPlaying {
                        MicroWaveformVisualizer(isPlaying: true)
                    }
                    
                    Button(action: onPlayToggle) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isPlaying ? Color.primary : Color.accentColor)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(isPlaying ? Color.primary.opacity(0.1) : Color.accentColor.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.all, 14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isActive ? Color.accentColor.opacity(0.03) : Color.primary.opacity(0.02))
            )
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isActive ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.06),
                        lineWidth: isActive ? 1.5 : 1
                    )
            )
            .shadow(
                color: isActive ? Color.accentColor.opacity(0.08) : Color.black.opacity(0.01),
                radius: 10,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fluid Avatar Component

struct FluidAvatarView: View {
    let voice: TTSVoice
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: gradientColors(for: voice.id),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Soft glossmorphic crescent lighting overlay for fluid liquid bubble effect
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(2)
            
            // Elegant serif initial letter
            Text(String(voice.name.prefix(1)))
                .font(.system(.title3, design: .serif).bold())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
        }
        .shadow(
            color: gradientColors(for: voice.id).first?.opacity(0.3) ?? .clear,
            radius: 8,
            x: 0,
            y: 4
        )
    }
    
    private func gradientColors(for voiceId: String) -> [Color] {
        switch voiceId {
        case "M1": return [Color(hex: "4A154B"), Color(hex: "1F2D5A"), Color(hex: "0F172A")] // Marcus: Deep Midnight Purple
        case "M2": return [Color(hex: "1A365D"), Color(hex: "2B6CB0"), Color(hex: "4A5568")] // Nathan: Professional Navy
        case "M3": return [Color(hex: "C05621"), Color(hex: "ED8936"), Color(hex: "ECC94B")] // Oliver: Warm Amber/Orange
        case "M4": return [Color(hex: "9B2C2C"), Color(hex: "E53E3E"), Color(hex: "DD6B20")] // Paul: Electric Red
        case "M5": return [Color(hex: "22543D"), Color(hex: "38A169"), Color(hex: "718096")] // Ryan: Classic Sage Green
        case "F1": return [Color(hex: "B83280"), Color(hex: "ED64A6"), Color(hex: "6B46C1")] // Alice: Sleek Violet/Pink
        case "F2": return [Color(hex: "D53F8C"), Color(hex: "F687B3"), Color(hex: "FED7E2")] // Beth: Soft YA Pink/Peach
        case "F3": return [Color(hex: "2C5282"), Color(hex: "319795"), Color(hex: "4FD1C5")] // Claire: Crisp Teal
        case "F4": return [Color(hex: "ECC94B"), Color(hex: "F6E05E"), Color(hex: "DD6B20")] // Diana: Bright Gold
        case "F5": return [Color(hex: "553C9A"), Color(hex: "805AD5"), Color(hex: "B794F4")] // Eve: Elegant Orchid
        default:
            let hash = abs(voiceId.hashValue)
            let systemPalettes: [[Color]] = [
                [Color(hex: "007AFF"), Color(hex: "5856D6"), Color(hex: "AF52DE")],
                [Color(hex: "30B0C7"), Color(hex: "34C759"), Color(hex: "007AFF")],
                [Color(hex: "FF2D55"), Color(hex: "FF9500"), Color(hex: "FFCC00")]
            ]
            return systemPalettes[hash % systemPalettes.count]
        }
    }
}

// MARK: - Micro Waveform Visualizer

struct MicroWaveformVisualizer: View {
    let isPlaying: Bool
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                TimelineView(.animation) { timeline in
                    let value = isPlaying ? amplitude(for: index, at: timeline.date.timeIntervalSince1970) : 0.15
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isPlaying ? Color.accentColor : Color.primary.opacity(0.3))
                        .frame(width: 3, height: max(4, value * 24))
                }
            }
        }
        .frame(height: 24)
    }
    
    private func amplitude(for index: Int, at time: TimeInterval) -> CGFloat {
        let speeds = [8.0, 11.0, 7.0, 13.0, 9.0]
        let phase = Double(index) * 1.2
        let sine = sin(time * speeds[index % 5] + phase)
        let normalized = (sine + 1.0) / 2.0 // 0 to 1
        return CGFloat(0.2 + normalized * 0.8) // 0.2 to 1.0
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Voice Sample Player

// Audio Engine & SpeechSynthesizer manager that plays voice preview samples
@MainActor
@Observable
final class VoiceSamplePlayer: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    
    // For model-generated voices:
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isEngineSetup = false
    private var synthesisTask: Task<Void, Never>?
    
    var playingVoiceId: String? = nil

    override init() {
        super.init()
        synth.delegate = self
    }

    private func getSampleText(for voice: TTSVoice) -> String {
        switch voice.id {
        case "M1":
            return "Hello! I am Marcus. My voice is deep and resonant, custom-crafted for epic fantasy novels and grand historical biographies."
        case "M2":
            return "Hello there! I am Nathan. With a clear and highly articulate delivery, I bring non-fiction and business audiobooks to life."
        case "M3":
            return "Hi, I'm Oliver. I provide a warm and engaging narrative tone, perfect for self-help guides, biographies, and memoirs."
        case "M4":
            return "Hey! I am Paul. My energetic and crisp pacing is perfect for keeping you on the edge of your seat during thrillers and sci-fi adventures."
        case "M5":
            return "Hello. I am Ryan. My smooth and classic narration is tailored for literature, romance, and reflective essays."
        case "F1":
            return "Hello! I am Alice. I offer a sleek and highly expressive reading style, ideal for modern fiction and mystery novels."
        case "F2":
            return "Hello there. I am Beth. My warm and comforting narration style is perfect for bedtime listening and young adult fiction."
        case "F3":
            return "Welcome! I am Claire. With a crisp, highly professional tone, I make complex educational and technical books easy to follow."
        case "F4":
            return "Hi! I am Diana. My bright and lively tone is wonderful for children's stories, comedy, and lighthearted tales."
        case "F5":
            return "Hello. I'm Eve. I deliver a soft, elegant narrative flow, bringing poetry, drama, and classic prose to life."
        default:
            return "Hello! I am \(voice.name). This is a preview of my voice in the Books App. Do you like my pronunciation?"
        }
    }

    func playSample(for voice: TTSVoice, synthesizer: SupertonicSynthesizer, activeSession: ReaderSession?) {
        // 1. Check if we are already playing this exact voice
        let alreadyPlayingSelected = (playingVoiceId == voice.id)
        
        // Always stop any current audio immediately
        stop()
        
        if alreadyPlayingSelected {
            // Tapped on the same voice: stop was requested, so we're done
            return
        }

        // 2. Cancel the active book reader session to prevent overlapping speech
        activeSession?.pause()

        playingVoiceId = voice.id

        if voice.id.hasPrefix("apple-") {
            // Apple System Voice Playback
            let sampleText = getSampleText(for: voice)
            let utterance = AVSpeechUtterance(string: sampleText)
            let identifier = String(voice.id.dropFirst(6))
            utterance.voice = AVSpeechSynthesisVoice(identifier: identifier)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synth.speak(utterance)
        } else {
            // Premium Model-Generated Playback using actual Supertonic ONNX synthesizer
            let sampleText = getSampleText(for: voice)
            let stream = synthesizer.synthesize(sampleText, voice: voice, options: SynthOptions())
            
            synthesisTask = Task {
                do {
                    var samples = [Float]()
                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        samples.append(contentsOf: chunk.samples)
                    }
                    
                    if Task.isCancelled { return }
                    
                    // Add subtle trailing silence for a natural transition
                    samples.append(contentsOf: [Float](repeating: 0.0, count: Int(0.075 * 44100)))
                    
                    guard let buffer = makePCMBuffer(from: samples) else {
                        playingVoiceId = nil
                        return
                    }
                    
                    setupPreviewEngine()
                    if !engine.isRunning {
                        try? engine.start()
                    }
                    
                    playerNode.play()
                    playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
                        Task { @MainActor in
                            guard let self else { return }
                            if self.playingVoiceId == voice.id {
                                self.playingVoiceId = nil
                            }
                        }
                    })
                } catch {
                    print("[VoiceSamplePlayer] Preview synthesis error: \(error)")
                    playingVoiceId = nil
                }
            }
        }
    }

    func stop() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        synthesisTask?.cancel()
        synthesisTask = nil
        playerNode.stop()
        playingVoiceId = nil
    }

    private func setupPreviewEngine() {
        guard !isEngineSetup else { return }
        engine.attach(playerNode)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        isEngineSetup = true
    }

    private func makePCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty else { return nil }

        var peak: Float = 0.0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        let normalized: [Float]
        if peak > 0.001 {
            var scale = Float(0.85) / peak
            var result = [Float](repeating: 0, count: samples.count)
            vDSP_vsmul(samples, 1, &scale, &result, 1, vDSP_Length(samples.count))
            normalized = result
        } else {
            normalized = samples
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(normalized.count)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(normalized.count)
        normalized.withUnsafeBufferPointer { ptr in
            if let dest = buffer.floatChannelData?[0] {
                dest.update(from: ptr.baseAddress!, count: normalized.count)
            }
        }
        return buffer
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.playingVoiceId = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.playingVoiceId = nil
        }
    }
}
