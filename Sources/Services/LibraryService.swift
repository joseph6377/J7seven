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
        return try? decoder.decode(SavedDocument.self, from: data)
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
