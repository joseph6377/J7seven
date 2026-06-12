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

    static let supportedLanguages: [String] = [
        "en", "ko", "ja", "ar", "bg", "cs", "da", "de", "el", "es", "et", "fi", "fr", "hi", "hr", "hu", "id", "it", "lt", "lv", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "tr", "uk", "vi"
    ]

    static let languageVoiceNames: [String: [String]] = [
        "en": ["Marcus", "Nathan", "Oliver", "Paul", "Ryan", "Alice", "Beth", "Claire", "Diana", "Eve"],
        "es": ["Mateo", "Santiago", "Alejandro", "Sebastián", "Javier", "Valentina", "Sofía", "Camila", "Isabella", "Valeria"],
        "fr": ["Gabriel", "Lucas", "Arthur", "Louis", "Hugo", "Emma", "Chloé", "Manon", "Léa", "Inès"],
        "de": ["Maximilian", "Lukas", "Jonas", "Finn", "Elias", "Marie", "Sophie", "Charlotte", "Emilia", "Mia"],
        "it": ["Leonardo", "Francesco", "Alessandro", "Lorenzo", "Mattia", "Sofia", "Aurora", "Giulia", "Ginevra", "Beatrice"],
        "pt": ["Miguel", "Arthur", "Heitor", "Bernardo", "Davi", "Helena", "Alice", "Laura", "Manuela", "Isabella"],
        "ja": ["Hiroto", "Ren", "Yuto", "Minato", "Haruto", "Himari", "Tsumugi", "Aoi", "Ichika", "Mei"],
        "ko": ["Minjun", "Seojun", "Doyun", "Yujun", "Eunwoo", "Seo-a", "Ji-an", "Hayoon", "Seoyoon", "Jiwoo"],
        "ru": ["Aleksandr", "Dmitri", "Mikhail", "Ivan", "Nikolai", "Anastasia", "Sofia", "Maria", "Daria", "Polina"],
        "ar": ["Omar", "Youssef", "Karim", "Ali", "Hassan", "Layla", "Fatima", "Mariam", "Nour", "Salma"],
        "hi": ["Aarav", "Vihaan", "Arjun", "Rohan", "Aditya", "Aanya", "Diya", "Saanvi", "Priya", "Isha"],
        "nl": ["Daan", "Luuk", "Bram", "Sem", "Milan", "Emma", "Sophie", "Julia", "Zoë", "Tess"],
        "pl": ["Antoni", "Jakub", "Jan", "Szymon", "Aleksander", "Zuzanna", "Julia", "Zofia", "Hanna", "Maja"],
        "sv": ["Elias", "Hugo", "Oliver", "Liam", "Alexander", "Alice", "Maja", "Elsa", "Astrid", "Wilma"],
        "da": ["William", "Noah", "Oskar", "Lucas", "Carl", "Emma", "Alma", "Ida", "Clara", "Sofia"],
        "fi": ["Leo", "Eino", "Oliver", "Elias", "Onni", "Aino", "Olivia", "Sofia", "Lilja", "Helmi"],
        "cs": ["Jakub", "Jan", "Tomáš", "Matyáš", "Filip", "Eliška", "Anna", "Adéla", "Tereza", "Sofie"],
        "sk": ["Jakub", "Samuel", "Michal", "Adam", "Filip", "Sofia", "Ema", "Nina", "Viktória", "Natália"],
        "sl": ["Luka", "Filip", "Jakob", "Nik", "Mark", "Zala", "Mia", "Hana", "Ema", "Julija"],
        "hr": ["Luka", "David", "Jakov", "Ivan", "Petar", "Mia", "Lucija", "Sara", "Nika", "Marta"],
        "hu": ["Bence", "Máté", "Levente", "Dávid", "Balázs", "Hanna", "Anna", "Zoé", "Luca", "Léna"],
        "ro": ["Andrei", "Alexandru", "Gabriel", "Ionuț", "Ștefan", "Maria", "Elena", "Ioana", "Andreea", "Alexandra"],
        "bg": ["Georgi", "Ivan", "Dimitar", "Aleksandar", "Nikola", "Maria", "Ivana", "Elena", "Yoana", "Alexandra"],
        "el": ["Georgios", "Ioannis", "Konstantinos", "Dimitrios", "Nikolaos", "Maria", "Eleni", "Aikaterini", "Vasiliki", "Sofia"],
        "et": ["Rasmus", "Robin", "Artjom", "Oliver", "Mark", "Sofia", "Eliise", "Sandra", "Laura", "Maria"],
        "lv": ["Roberts", "Gustavs", "Daniels", "Aleksandrs", "Maksims", "Sofija", "Emilija", "Alise", "Marta", "Anna"],
        "lt": ["Dominykas", "Jonas", "Lukas", "Matas", "Kajus", "Emilija", "Gabija", "Austėja", "Ugnė", "Kamilė"],
        "tr": ["Yusuf", "Mustafa", "Ahmet", "Ömer", "Ali", "Zeynep", "Elif", "Defne", "Hiranur", "Eylül"],
        "uk": ["Artem", "Oleksandr", "Dmytro", "Vladyslav", "Maksym", "Sofiya", "Anastasiya", "Mariya", "Anna", "Viktoriya"],
        "vi": ["Minh", "Nam", "Duc", "Huy", "Phong", "Linh", "Hoa", "Lan", "Mai", "Vy"],
        "id": ["Budi", "Joko", "Agus", "Hendra", "Aditya", "Siti", "Dewi", "Sri", "Putri", "Indah"]
    ]

    static func nameFor(baseId: String, lang: String) -> String {
        let names = languageVoiceNames[lang] ?? languageVoiceNames["en"]!
        let index: Int
        switch baseId {
        case "M1": index = 0
        case "M2": index = 1
        case "M3": index = 2
        case "M4": index = 3
        case "M5": index = 4
        case "F1": index = 5
        case "F2": index = 6
        case "F3": index = 7
        case "F4": index = 8
        case "F5": index = 9
        default: index = 0
        }
        return names[index]
    }

    /// Voice IDs match the filenames in Supertone/supertonic-3/voice_styles/ on HuggingFace.
    /// Dynamically generated for all supported languages.
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

        var allVoices = [TTSVoice]()
        for lang in supportedLanguages {
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
