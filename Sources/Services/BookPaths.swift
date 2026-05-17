import Foundation

enum BookPaths {
    static func booksRoot() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("books", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func bookDirectory(slug: String) -> URL {
        let dir = booksRoot().appendingPathComponent(slug, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func localURL(slug: String, filename: String) -> URL {
        let bookDir = bookDirectory(slug: slug)
        // If the filename is an absolute path or relative path from OPF, 
        // we try to find it relative to the book root.
        let fileURL = bookDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        
        // EPUBs often have a content folder (OEBPS). If not found at root, search recursively.
        let enumerator = FileManager.default.enumerator(at: bookDir, includingPropertiesForKeys: nil)
        let lastPart = (filename as NSString).lastPathComponent
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == lastPart {
                return url
            }
        }
        
        return fileURL
    }
}
