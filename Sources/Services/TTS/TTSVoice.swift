import Foundation

struct TTSVoice: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let language: String
    let gender: Gender

    enum Gender: String, Codable {
        case male, female
    }

    static let `default` = TTSVoice(id: "M1", name: "Marcus", language: "en", gender: .male)

    /// Voice IDs match the filenames in Supertone/supertonic-3/voice_styles/ on HuggingFace.
    static func loadAll() -> [TTSVoice] {
        [
            TTSVoice(id: "M1", name: "Marcus", language: "en", gender: .male),
            TTSVoice(id: "M2", name: "Nathan", language: "en", gender: .male),
            TTSVoice(id: "M3", name: "Oliver", language: "en", gender: .male),
            TTSVoice(id: "M4", name: "Paul",   language: "en", gender: .male),
            TTSVoice(id: "M5", name: "Ryan",   language: "en", gender: .male),
            TTSVoice(id: "F1", name: "Alice",  language: "en", gender: .female),
            TTSVoice(id: "F2", name: "Beth",   language: "en", gender: .female),
            TTSVoice(id: "F3", name: "Claire", language: "en", gender: .female),
            TTSVoice(id: "F4", name: "Diana",  language: "en", gender: .female),
            TTSVoice(id: "F5", name: "Eve",    language: "en", gender: .female),
        ]
    }
}
