import Foundation
import AVFoundation
import OnnxRuntimeBindings

enum ModelState {
    case notDownloaded
    case downloading(progress: Double)
    case loading
    case ready
    case error(String)
}

@Observable
@MainActor
final class SupertonicService {

    private var modelDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models/supertonic", isDirectory: true)
    }

    var modelState: ModelState = .notDownloaded

    /// Approximate real-time factor: audioSeconds / wallClockSeconds
    var realtimeFactor: Double = 1.0

    private var tts: TextToSpeech?
    private var ortEnv: ORTEnv?

    // HuggingFace model repository base URL
    private static let hfBase = "https://huggingface.co/Supertone/supertonic-3/resolve/main"

    // All files to download, with approximate sizes for progress tracking
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

    func checkAndPrepare() {
        let sentinel = modelDirectory
            .appendingPathComponent("onnx/vocoder.onnx")
        if FileManager.default.fileExists(atPath: sentinel.path) {
            modelState = .loading
            Task { await loadModel() }
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

            // Skip already-downloaded files (resume support)
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
        do {
            let onnxDir = modelDirectory.appendingPathComponent("onnx").path
            let env = try ORTEnv(loggingLevel: .warning)
            ortEnv = env
            tts = try loadTextToSpeech(onnxDir, false, env)
            modelState = .ready
        } catch {
            modelState = .error(error.localizedDescription)
        }
    }

    // MARK: - Synthesis

    /// Synthesise one paragraph of plain text.
    /// Returns a 44 100 Hz mono float32 PCM buffer ready for AVAudioEngine.
    func synthesize(text: String, voice: TTSVoice) async throws -> AVAudioPCMBuffer {
        guard case .ready = modelState, let tts else {
            throw NSError(domain: "SupertonicService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        let start = Date()

        let styleJSON = modelDirectory
            .appendingPathComponent("voice_styles")
            .appendingPathComponent("\(voice.id).json").path
        let style = try loadVoiceStyle([styleJSON], verbose: false)

        let (wav, audioDuration) = try tts.call(
            text, voice.language, style,
            8,                          // denoising steps (quality vs. speed: 5–12)
            speed: 1.0,
            silenceDuration: 0.3
        )

        realtimeFactor = Double(audioDuration) / max(Date().timeIntervalSince(start), 0.001)
        return makePCMBuffer(from: wav)
    }

    // MARK: - [Float] → AVAudioPCMBuffer

    private func makePCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData![0].update(
                from: ptr.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
