import Foundation

@Observable
final class LibraryService: @unchecked Sendable {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func scanLocalLibrary() -> [LibraryEntry] {
        let root = LibraryPaths.libraryRoot()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.compactMap { file -> LibraryEntry? in
            guard file.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: file),
                  let doc = try? decoder.decode(SavedDocument.self, from: data)
            else { return nil }
            return LibraryEntry(from: doc)
        }
        .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    func loadDocument(id: UUID) -> SavedDocument? {
        let url = LibraryPaths.documentURL(id: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let doc = try? decoder.decode(SavedDocument.self, from: data) else { return nil }
        
        // Dynamically sanitize paragraph texts to collapse newlines and redundant spaces
        let sanitizedChapters = doc.chapters.map { chapter in
            let sanitizedParagraphs = chapter.paragraphs.map { para in
                let sanitizedText = para.text.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                return Paragraph(text: sanitizedText, pageNumber: para.pageNumber)
            }
            return ChapterText(index: chapter.index, title: chapter.title, paragraphs: sanitizedParagraphs)
        }
        
        return SavedDocument(
            id: doc.id,
            title: doc.title,
            author: doc.author,
            coverImageData: doc.coverImageData,
            importedAt: doc.importedAt,
            lastOpenedAt: doc.lastOpenedAt,
            chapters: sanitizedChapters,
            cursor: doc.cursor,
            sourceFormat: doc.sourceFormat,
            pageCount: doc.pageCount,
            sourceURL: doc.sourceURL
        )
    }

    func saveDocument(_ doc: SavedDocument) {
        let url = LibraryPaths.documentURL(id: doc.id)
        guard let data = try? encoder.encode(doc) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func deleteDocument(id: UUID) {
        let url = LibraryPaths.documentURL(id: id)
        try? FileManager.default.removeItem(at: url)
    }
}
