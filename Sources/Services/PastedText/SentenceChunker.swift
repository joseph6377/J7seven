import Foundation
import NaturalLanguage

enum SentenceChunker {
    static func chunk(_ text: String, targetWordCount: Int = 150) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines))
            return true
        }
        
        var paragraphs: [String] = []
        var current: [String] = []
        var currentWords = 0
        for sentence in sentences where !sentence.isEmpty {
            let words = sentence.split(whereSeparator: \.isWhitespace).count
            current.append(sentence)
            currentWords += words
            if currentWords >= targetWordCount {
                paragraphs.append(current.joined(separator: " "))
                current.removeAll()
                currentWords = 0
            }
        }
        if !current.isEmpty {
            paragraphs.append(current.joined(separator: " "))
        }
        return paragraphs
    }
}
