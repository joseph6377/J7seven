import Foundation
import AVFoundation

// ─────────────────────────────────────────────────────────────────────────────
// INTEGRATION CHECKLIST (do these before implementing the TODO blocks):
//
// 1. Clone https://github.com/supertone-inc/supertonic
// 2. Copy  supertonic/swift/Sources/Helper.swift
//       →  Sources/Services/TTS/SupertonicHelper.swift
// 3. Copy  supertonic/ios/ExampleiOSApp/ExampleiOSApp/TTSService.swift
//       →  Sources/Services/TTS/SupertonicONNX.swift
// 4. Audit those files for the real API (function names, params, return types)
//    and update the TODO blocks below accordingly.
// 5. Find the ONNX model download URL in supertonic's README / GitHub releases
//    and set modelDownloadURL below.
// 6. Add to project.yml under packages + target dependencies:
//      onnxruntime:
//        url: https://github.com/microsoft/onnxruntime-swift-package-manager
//        from: 1.16.0
// ─────────────────────────────────────────────────────────────────────────────

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

    // TODO: Set real download URL from supertonic releases page
    private let modelDownloadURL = URL(string: "https://TODO_SUPERTONIC_MODEL_URL")!

    private var modelDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models/supertonic", isDirectory: true)
    }

    var modelState: ModelState = .notDownloaded

    /// Approximate real-time factor: audioSeconds / wallClockSeconds
    var realtimeFactor: Double = 1.0

    // TODO: Hold reference to loaded ONNX session after inspecting SupertonicONNX.swift
    // private var session: SupertonicTTSService?

    // MARK: - Model lifecycle

    func checkAndPrepare() {
        let exists = FileManager.default.fileExists(atPath: modelDirectory.path)
        if exists {
            modelState = .loading
            Task { await loadModel() }
        } else {
            modelState = .notDownloaded
        }
    }

    func downloadModel() async throws {
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        modelState = .downloading(progress: 0)

        // TODO: Download model weights with URLSession + progress reporting.
        // The model is likely a ZIP — extract to modelDirectory after download.
        //
        // let (tempURL, _) = try await URLSession.shared.download(from: modelDownloadURL)
        // try ZipExtractor.extract(tempURL, to: modelDirectory)
        // modelState = .loading
        // await loadModel()

        throw NSError(domain: "SupertonicService", code: 0,
                      userInfo: [NSLocalizedDescriptionKey: "TODO: set modelDownloadURL and implement download"])
    }

    private func loadModel() async {
        // TODO: Initialise ONNX session via SupertonicONNX.swift
        // session = try? SupertonicTTSService(modelDir: modelDirectory.path)
        modelState = .ready
    }

    // MARK: - Synthesis

    /// Synthesise one paragraph of plain text.
    /// Returns 44.1 kHz mono float32 PCM buffer ready for AVAudioEngine scheduling.
    func synthesize(text: String, voice: TTSVoice) async throws -> AVAudioPCMBuffer {
        guard case .ready = modelState else {
            throw NSError(domain: "SupertonicService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        let start = Date()

        // TODO: Call the real Supertonic inference API after inspecting SupertonicONNX.swift.
        // Expected shape (mirrors Python API):
        //
        //   let (wavData, audioDuration) = try session!.synthesize(
        //       text:       text,
        //       lang:       voice.language,
        //       voiceStyle: voice.id,
        //       steps:      8,        // quality 5–12
        //       speed:      1.0
        //   )
        //
        // Then convert the returned Data (44100 Hz mono 16-bit PCM) → AVAudioPCMBuffer:
        //   let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
        //                              sampleRate: 44100, channels: 1, interleaved: true)!
        //   let frameCount = wavData.count / 2
        //   let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        //   buffer.frameLength = AVAudioFrameCount(frameCount)
        //   wavData.withUnsafeBytes { ptr in
        //       buffer.int16ChannelData![0].update(from: ptr.baseAddress!.assumingMemoryBound(to: Int16.self),
        //                                          count: frameCount)
        //   }
        //   realtimeFactor = audioDuration / Date().timeIntervalSince(start)
        //   return buffer

        throw NSError(domain: "SupertonicService", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "TODO: implement synthesis"])
    }
}
