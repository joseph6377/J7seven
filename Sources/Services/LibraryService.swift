import Foundation

@Observable
final class LibraryService: @unchecked Sendable {
    private let decoder = JSONDecoder()

    func scanLocalLibrary() -> [LibraryEntry] {
        let root = BookPaths.booksRoot()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.compactMap { dir -> LibraryEntry? in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(BookManifest.self, from: data)
            else { return nil }
            return LibraryEntry(from: manifest)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func manifest(slug: String) -> BookManifest? {
        let url = BookPaths.bookDirectory(slug: slug).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(BookManifest.self, from: data)
    }

    func loadProgress(slug: String) -> ReadingProgress {
        let key = "progress:\(slug)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? decoder.decode(ReadingProgress.self, from: data)
        else { return ReadingProgress() }
        return p
    }

    func saveProgress(_ progress: ReadingProgress, slug: String) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: "progress:\(slug)")
    }

    func deleteBook(slug: String) {
        let dir = BookPaths.bookDirectory(slug: slug)
        try? FileManager.default.removeItem(at: dir)
    }
}
