import Foundation

struct TTSVoice: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let language: String
    let gender: Gender

    enum Gender: String, Codable {
        case male, female
    }

    static let `default` = TTSVoice(id: "en-male-1", name: "Alex", language: "en", gender: .male)

    /// Load available voices from bundled Resources/tts-voices/*.json
    /// TODO: Replace placeholder list with real Supertonic voice IDs after
    ///       inspecting supertonic/assets/ voice style JSON files.
    static func loadAll() -> [TTSVoice] {
        [
            TTSVoice(id: "en-male-1",   name: "Alex",  language: "en", gender: .male),
            TTSVoice(id: "en-female-1", name: "Sarah", language: "en", gender: .female),
        ]
    }
}
