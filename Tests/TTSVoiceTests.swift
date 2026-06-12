import XCTest
@testable import BooksAppV2

final class TTSVoiceTests: XCTestCase {

    func testSupportedLanguagesCountAndFirst() {
        XCTAssertEqual(TTSVoice.supportedLanguages.count, 31)
        XCTAssertEqual(TTSVoice.supportedLanguages.first, "en")
    }

    func testLoadAllVoicesCount() {
        let allVoices = TTSVoice.loadAll()
        // 31 languages, each with 10 voices (M1..M5, F1..F5)
        XCTAssertEqual(allVoices.count, 310)
    }

    func testDefaultVoice() {
        let def = TTSVoice.default
        XCTAssertEqual(def.id, "M1-en")
        XCTAssertEqual(def.name, "Marcus")
        XCTAssertEqual(def.language, "en")
        XCTAssertEqual(def.gender, .male)
    }

    func testVoiceNameMapping() {
        // Original language names
        XCTAssertEqual(TTSVoice.nameFor(baseId: "M1", lang: "en"), "Marcus")
        XCTAssertEqual(TTSVoice.nameFor(baseId: "F1", lang: "en"), "Alice")
        XCTAssertEqual(TTSVoice.nameFor(baseId: "M1", lang: "es"), "Mateo")
        XCTAssertEqual(TTSVoice.nameFor(baseId: "F1", lang: "es"), "Valentina")
        XCTAssertEqual(TTSVoice.nameFor(baseId: "M1", lang: "fr"), "Gabriel")
        XCTAssertEqual(TTSVoice.nameFor(baseId: "F1", lang: "fr"), "Emma")

        // New language names
        XCTAssertEqual(TTSVoice.nameFor(baseId: "M1", lang: "ru"), "Aleksandr")
        XCTAssertEqual(TTSVoice.nameFor(baseId: "F1", lang: "ru"), "Anastasia")
        XCTAssertEqual(TTSVoice.nameFor(baseId: "M2", lang: "ar"), "Youssef")
        XCTAssertEqual(TTSVoice.nameFor(baseId: "F2", lang: "ar"), "Fatima")
        XCTAssertEqual(TTSVoice.nameFor(baseId: "M1", lang: "hi"), "Aarav")
        XCTAssertEqual(TTSVoice.nameFor(baseId: "F1", lang: "hi"), "Aanya")

        // Fallback to English for unknown/unsupported language
        XCTAssertEqual(TTSVoice.nameFor(baseId: "M1", lang: "unknown"), "Marcus")
    }
}
