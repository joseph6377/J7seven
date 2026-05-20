import AVFoundation
import Foundation

enum TTSEngine: String, CaseIterable, Identifiable {
    case supertonic = "supertonic"
    case apple      = "apple"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .supertonic: return "Supertonic 3"
        case .apple:      return "Apple Natural Voice"
        }
    }
}

enum AppleVoiceMapper {
    private static let genderMap: [String: TTSVoice.Gender] = [
        "Ava": .female, "Samantha": .female, "Allison": .female,
        "Victoria": .female, "Susan": .female, "Karen": .female,
        "Moira": .female, "Tessa": .female, "Fiona": .female,
        "Stephanie": .female, "Zoe": .female, "Kate": .female,
        "Nicky": .female, "Siri": .female,
        "Tom": .male, "Daniel": .male, "Alex": .male,
        "Fred": .male, "Oliver": .male, "Arthur": .male,
        "Gordon": .male, "Rishi": .male, "Aaron": .male,
    ]

    static func availableVoices() -> [TTSVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices()

        let english = all.filter {
            ($0.language.hasPrefix("en-US") || $0.language.hasPrefix("en-GB") ||
             $0.language.hasPrefix("en-AU"))
            && ($0.quality == .premium || $0.quality == .enhanced)
        }

        let sorted = english.sorted {
            if $0.quality.rawValue != $1.quality.rawValue {
                return $0.quality.rawValue > $1.quality.rawValue
            }
            return $0.name < $1.name
        }

        var seen = Set<String>()
        let deduped = sorted.filter { seen.insert($0.name).inserted }
        let capped = Array(deduped.prefix(8))

        if capped.isEmpty {
            if let fallback = AVSpeechSynthesisVoice(language: "en-US") {
                return [TTSVoice(
                    id: "apple-\(fallback.identifier)",
                    name: fallback.name,
                    language: "en",
                    gender: genderMap[fallback.name] ?? .female
                )]
            }
            return []
        }

        return capped.map { av in
            TTSVoice(
                id: "apple-\(av.identifier)",
                name: av.name,
                language: "en",
                gender: genderMap[av.name] ?? .female
            )
        }
    }

    static func avVoice(for ttsVoice: TTSVoice) -> AVSpeechSynthesisVoice? {
        guard ttsVoice.id.hasPrefix("apple-") else { return nil }
        let identifier = String(ttsVoice.id.dropFirst(6))
        return AVSpeechSynthesisVoice(identifier: identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    static func hasPremiumVoice() -> Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { $0.quality == .premium }
    }
}
