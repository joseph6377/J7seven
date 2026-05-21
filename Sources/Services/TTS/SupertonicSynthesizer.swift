import Foundation
import AVFoundation
@preconcurrency import OnnxRuntimeBindings

enum ModelState {
    case notDownloaded
    case downloading(progress: Double)
    case loading
    case ready
    case error(String)
}

struct PCMChunk: Sendable {
    let samples: [Float]
    let sampleRate: Double      // 44_100
    let isFinal: Bool           // last chunk for this paragraph
}

struct SynthOptions: Sendable {
    var steps: Int = 4          // Supertonic inference steps (2…5)
    var speed: Double = 1.0     // text-level; player-level scaling also possible
}

@MainActor
protocol Synthesizer {
    /// Synthesize one paragraph. Returns PCM float32 @ 44.1 kHz mono.
    /// May yield multiple chunks; caller concatenates or schedules each.
    func synthesize(_ text: String, voice: TTSVoice, options: SynthOptions) -> AsyncThrowingStream<PCMChunk, Error>
    func cancelAll()
}

@Observable
@MainActor
final class SupertonicSynthesizer: Synthesizer {

    private var modelDirectory: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models/supertonic", isDirectory: true)
    }

    /// Resolves the actual directory path or file URL where a model asset is located,
    /// searching first in the main app bundle (flat or nested) and falling back to caches.
    private func resolvePath(for fileOrFolder: String) -> URL {
        // 1. Check if the asset is bundled in the App Bundle (supporting flat or nested subdirectories)
        if fileOrFolder == "onnx" {
            if let vocoderURL = Bundle.main.url(forResource: "vocoder", withExtension: "onnx") {
                return vocoderURL.deletingLastPathComponent()
            }
            if let vocoderURL = Bundle.main.url(forResource: "vocoder", withExtension: "onnx", subdirectory: "Models/supertonic/onnx") {
                return vocoderURL.deletingLastPathComponent()
            }
        } else if fileOrFolder == "voice_styles" {
            if let m1URL = Bundle.main.url(forResource: "M1", withExtension: "json") {
                return m1URL.deletingLastPathComponent()
            }
            if let m1URL = Bundle.main.url(forResource: "M1", withExtension: "json", subdirectory: "Models/supertonic/voice_styles") {
                return m1URL.deletingLastPathComponent()
            }
        } else if fileOrFolder.hasPrefix("voice_styles/") {
            let filename = URL(fileURLWithPath: fileOrFolder).deletingPathExtension().lastPathComponent
            if let styleURL = Bundle.main.url(forResource: filename, withExtension: "json") {
                return styleURL
            }
            if let styleURL = Bundle.main.url(forResource: filename, withExtension: "json", subdirectory: "Models/supertonic/voice_styles") {
                return styleURL
            }
        }

        // 2. Fall back to local Caches directory (downloaded path)
        return modelDirectory.appendingPathComponent(fileOrFolder)
    }

    var modelState: ModelState = .notDownloaded

    /// Approximate real-time factor: audioSeconds / wallClockSeconds
    var realtimeFactor: Double = 1.0

    private var tts: TextToSpeech?
    private var ortEnv: ORTEnv?

    // HuggingFace model repository base URL
    private static let hfBase = "https://huggingface.co/Supertone/supertonic-3/resolve/main"

    // All files to download
    private static let modelFiles: [(path: String, size: Int)] = [
        ("onnx/tts.json",                   8_250),
        ("onnx/unicode_indexer.json",      278_000),
        ("onnx/duration_predictor.onnx", 3_700_000),
        ("onnx/text_encoder.onnx",       36_400_000),
        ("onnx/vocoder.onnx",           101_000_000),
        ("onnx/vector_estimator.onnx",  257_000_000),
        ("voice_styles/F1.json",           292_000),
        ("voice_styles/F2.json",           292_000),
        ("voice_styles/F3.json",           291_000),
        ("voice_styles/F4.json",           292_000),
        ("voice_styles/F5.json",           291_000),
        ("voice_styles/M1.json",           292_000),
        ("voice_styles/M2.json",           292_000),
        ("voice_styles/M3.json",           290_000),
        ("voice_styles/M4.json",           292_000),
        ("voice_styles/M5.json",           291_000),
    ]

    private static let totalBytes = modelFiles.reduce(0) { $0 + $1.size }

    // MARK: - Model lifecycle

    private func migrateOldModelsIfNeeded() {
        let fm = FileManager.default
        let oldModelDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models/supertonic", isDirectory: true)
        
        let oldSentinel = oldModelDirectory.appendingPathComponent("onnx/vocoder.onnx")
        let newSentinel = modelDirectory.appendingPathComponent("onnx/vocoder.onnx")
        
        if fm.fileExists(atPath: oldSentinel.path) {
            if !fm.fileExists(atPath: newSentinel.path) {
                print("[SupertonicSynthesizer] Found voice models in old Documents folder. Migrating to Caches directory...")
                do {
                    try fm.createDirectory(at: modelDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
                    
                    if fm.fileExists(atPath: modelDirectory.path) {
                        try fm.removeItem(at: modelDirectory)
                    }
                    
                    try fm.moveItem(at: oldModelDirectory, to: modelDirectory)
                    print("[SupertonicSynthesizer] Successfully migrated models to Caches folder.")
                } catch {
                    print("[SupertonicSynthesizer] Error migrating old models: \(error)")
                }
            } else {
                print("[SupertonicSynthesizer] Models already migrated to Caches. Cleaning up old Documents/Models directory...")
            }
            
            if fm.fileExists(atPath: oldModelDirectory.path) {
                do {
                    try fm.removeItem(at: oldModelDirectory)
                    print("[SupertonicSynthesizer] Cleaned up old models directory in Documents.")
                } catch {
                    print("[SupertonicSynthesizer] Error cleaning up old models directory: \(error)")
                }
            }
        }
    }

    func checkAndPrepare() {
        migrateOldModelsIfNeeded()

        // 1. Proactively check if models are bundled in the App Bundle (Strategy A)
        if Bundle.main.url(forResource: "vocoder", withExtension: "onnx") != nil ||
           Bundle.main.url(forResource: "vocoder", withExtension: "onnx", subdirectory: "Models/supertonic/onnx") != nil {
            print("[SupertonicSynthesizer] Detected bundled voice models in App Bundle. Skipping download phase.")
            modelState = .loading
            Task {
                await self.loadModel()
            }
            return
        }

        // 2. Fall back to checking local caches folder
        let sentinel = modelDirectory.appendingPathComponent("onnx/vocoder.onnx")
        if FileManager.default.fileExists(atPath: sentinel.path) {
            modelState = .loading
            Task {
                await self.loadModel()
            }
        } else {
            modelState = .notDownloaded
        }
    }

    func downloadModel() async throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: modelDirectory.appendingPathComponent("onnx"),
            withIntermediateDirectories: true)
        try fm.createDirectory(
            at: modelDirectory.appendingPathComponent("voice_styles"),
            withIntermediateDirectories: true)

        var downloadedBytes = 0
        modelState = .downloading(progress: 0)

        for file in Self.modelFiles {
            let dest = modelDirectory.appendingPathComponent(file.path)

            if fm.fileExists(atPath: dest.path) {
                downloadedBytes += file.size
                modelState = .downloading(
                    progress: Double(downloadedBytes) / Double(Self.totalBytes))
                continue
            }

            guard let url = URL(string: "\(Self.hfBase)/\(file.path)") else { continue }
            let (tmpURL, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                try? fm.removeItem(at: tmpURL)
                throw URLError(.badServerResponse)
            }
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: tmpURL, to: dest)

            downloadedBytes += file.size
            modelState = .downloading(
                progress: Double(downloadedBytes) / Double(Self.totalBytes))
        }

        modelState = .loading
        await loadModel()
    }

    private func loadModel() async {
        let onnxDirURL = resolvePath(for: "onnx")
        let onnxDir = onnxDirURL.path
        
        // ORTEnv and TextToSpeech creation can be slow and use sync primitives.
        // Run it on a dedicated Grand Central Dispatch thread instead of the Swift Concurrency cooperative thread pool
        // to prevent "unsafeForcedSync" runtime warnings and Cooperative Thread Pool starvation.
        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let env = try ORTEnv(loggingLevel: .warning)
                    let loadedTTS = try loadTextToSpeech(onnxDir, false, env)
                    continuation.resume(returning: Result<(ORTEnv, TextToSpeech), Error>.success((env, loadedTTS)))
                } catch {
                    continuation.resume(returning: Result<(ORTEnv, TextToSpeech), Error>.failure(error))
                }
            }
        }

        switch result {
        case .success(let (env, loadedTTS)):
            self.ortEnv = env
            self.tts = loadedTTS
            self.modelState = .ready
        case .failure(let error):
            print("[SupertonicSynthesizer] Failed to load model from \(onnxDir): \(error)")
            self.modelState = .error(error.localizedDescription)
        }
    }

    // MARK: - Synthesizer Protocol

    func synthesize(_ text: String, voice: TTSVoice, options: SynthOptions) -> AsyncThrowingStream<PCMChunk, Error> {
        // Capture needed state to avoid accessing main actor properties from background
        guard let tts = self.tts else {
            return AsyncThrowingStream { $0.finish(throwing: NSError(domain: "SupertonicSynthesizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])) }
        }
        
        let resolvedVoiceStylePath: String
        let styleFile = "voice_styles/\(voice.id).json"
        let resolvedURL = resolvePath(for: styleFile)
            
        // Graceful fallback to default Marcus (M1) if the voice style file does not exist
        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            resolvedVoiceStylePath = resolvedURL.path
        } else {
            let fallbackURL = resolvePath(for: "voice_styles/M1.json")
            print("[SupertonicSynthesizer] Voice style file not found at \(resolvedURL.path). Falling back to M1.")
            resolvedVoiceStylePath = fallbackURL.path
        }
        
        let language = voice.language
        let steps = options.steps
        let speed = options.speed
        
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    let style = try await withCheckedThrowingContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            do {
                                let loadedStyle = try loadVoiceStyle([resolvedVoiceStylePath], verbose: false)
                                continuation.resume(returning: loadedStyle)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                    
                    let maxLen = (language == "ko" || language == "ja") ? 120 : 300
                    let chunks = chunkText(text, maxLen: maxLen)

                    for (i, chunkText) in chunks.enumerated() {
                        if Task.isCancelled { break }
                        
                        let start = Date()
                        // Synchronous blocking call to ONNX Runtime offloaded to GCD to prevent blocking cooperative pool
                        let result = try await withCheckedThrowingContinuation { continuation in
                            DispatchQueue.global(qos: .userInitiated).async {
                                do {
                                    let callResult = try tts.call(
                                        chunkText, language, style,
                                        steps,
                                        speed: Float(speed),
                                        silenceDuration: 0.05
                                    )
                                    continuation.resume(returning: callResult)
                                } catch {
                                    continuation.resume(throwing: error)
                                }
                            }
                        }
                        
                        let audioDuration = Double(result.duration)
                        let factor = audioDuration / max(Date().timeIntervalSince(start), 0.001)
                        
                        if let self = self {
                            // Update UI properties on main actor
                            await MainActor.run {
                                self.realtimeFactor = factor
                            }
                        }

                        let isFinal = i == chunks.count - 1
                        continuation.yield(PCMChunk(
                            samples: result.wav,
                            sampleRate: 44100,
                            isFinal: isFinal
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func cancelAll() {
        // Task handles cancellation automatically via AsyncThrowingStream's onTermination
    }
}
