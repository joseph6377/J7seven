import Foundation

struct TTSVoice: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let language: String
    let gender: Gender

    enum Gender: String, Codable {
        case male, female
    }

    static let `default` = TTSVoice(id: "M1-en", name: "Marcus", language: "en", gender: .male)

    static func nameFor(baseId: String, lang: String) -> String {
        switch lang {
        case "es":
            switch baseId {
            case "M1": return "Mateo"
            case "M2": return "Santiago"
            case "M3": return "Alejandro"
            case "M4": return "Sebastián"
            case "M5": return "Javier"
            case "F1": return "Valentina"
            case "F2": return "Sofía"
            case "F3": return "Camila"
            case "F4": return "Isabella"
            case "F5": return "Valeria"
            default: return "Mateo"
            }
        case "fr":
            switch baseId {
            case "M1": return "Gabriel"
            case "M2": return "Lucas"
            case "M3": return "Arthur"
            case "M4": return "Louis"
            case "M5": return "Hugo"
            case "F1": return "Emma"
            case "F2": return "Chloé"
            case "F3": return "Manon"
            case "F4": return "Léa"
            case "F5": return "Inès"
            default: return "Gabriel"
            }
        case "de":
            switch baseId {
            case "M1": return "Maximilian"
            case "M2": return "Lukas"
            case "M3": return "Jonas"
            case "M4": return "Finn"
            case "M5": return "Elias"
            case "F1": return "Marie"
            case "F2": return "Sophie"
            case "F3": return "Charlotte"
            case "F4": return "Emilia"
            case "F5": return "Mia"
            default: return "Maximilian"
            }
        case "it":
            switch baseId {
            case "M1": return "Leonardo"
            case "M2": return "Francesco"
            case "M3": return "Alessandro"
            case "M4": return "Lorenzo"
            case "M5": return "Mattia"
            case "F1": return "Sofia"
            case "F2": return "Aurora"
            case "F3": return "Giulia"
            case "F4": return "Ginevra"
            case "F5": return "Beatrice"
            default: return "Leonardo"
            }
        case "pt":
            switch baseId {
            case "M1": return "Miguel"
            case "M2": return "Arthur"
            case "M3": return "Heitor"
            case "M4": return "Bernardo"
            case "M5": return "Davi"
            case "F1": return "Helena"
            case "F2": return "Alice"
            case "F3": return "Laura"
            case "F4": return "Manuela"
            case "F5": return "Isabella"
            default: return "Miguel"
            }
        case "ja":
            switch baseId {
            case "M1": return "Hiroto"
            case "M2": return "Ren"
            case "M3": return "Yuto"
            case "M4": return "Minato"
            case "M5": return "Haruto"
            case "F1": return "Himari"
            case "F2": return "Tsumugi"
            case "F3": return "Aoi"
            case "F4": return "Ichika"
            case "F5": return "Mei"
            default: return "Hiroto"
            }
        case "ko":
            switch baseId {
            case "M1": return "Minjun"
            case "M2": return "Seojun"
            case "M3": return "Doyun"
            case "M4": return "Yujun"
            case "M5": return "Eunwoo"
            case "F1": return "Seo-a"
            case "F2": return "Ji-an"
            case "F3": return "Hayoon"
            case "F4": return "Seoyoon"
            case "F5": return "Jiwoo"
            default: return "Minjun"
            }
        default: // English fallback
            switch baseId {
            case "M1": return "Marcus"
            case "M2": return "Nathan"
            case "M3": return "Oliver"
            case "M4": return "Paul"
            case "M5": return "Ryan"
            case "F1": return "Alice"
            case "F2": return "Beth"
            case "F3": return "Claire"
            case "F4": return "Diana"
            case "F5": return "Eve"
            default: return "Marcus"
            }
        }
    }

    /// Voice IDs match the filenames in Supertone/supertonic-3/voice_styles/ on HuggingFace.
    /// Dynamically generated for all 8 supported languages.
    static func loadAll() -> [TTSVoice] {
        let baseVoices = [
            (id: "M1", gender: Gender.male),
            (id: "M2", gender: Gender.male),
            (id: "M3", gender: Gender.male),
            (id: "M4", gender: Gender.male),
            (id: "M5", gender: Gender.male),
            (id: "F1", gender: Gender.female),
            (id: "F2", gender: Gender.female),
            (id: "F3", gender: Gender.female),
            (id: "F4", gender: Gender.female),
            (id: "F5", gender: Gender.female)
        ]

        let languages = ["en", "es", "fr", "de", "ja", "ko", "it", "pt"]

        var allVoices = [TTSVoice]()
        for lang in languages {
            for base in baseVoices {
                let name = nameFor(baseId: base.id, lang: lang)
                allVoices.append(TTSVoice(
                    id: "\(base.id)-\(lang)",
                    name: name,
                    language: lang,
                    gender: base.gender
                ))
            }
        }
        return allVoices
    }
}
