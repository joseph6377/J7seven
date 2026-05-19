import Foundation

enum LibraryPaths {
    static func libraryRoot() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("library", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func documentURL(id: UUID) -> URL {
        return libraryRoot().appendingPathComponent("\(id.uuidString).json")
    }
}
