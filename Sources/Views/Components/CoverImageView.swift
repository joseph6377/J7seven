import SwiftUI

struct CoverImageView: View {
    @Environment(AppState.self) private var appState
    let id: UUID
    @State private var coverData: Data?

    // Deterministic gradient per book based on id
    private var placeholderGradient: LinearGradient {
        let hash = abs(id.hashValue)
        let palettes: [(Color, Color)] = [
            (.purple, .indigo),
            (.teal, .blue),
            (.orange, .pink),
            (.green, .teal),
            (.indigo, .purple),
            (.pink, .orange),
        ]
        let (a, b) = palettes[hash % palettes.count]
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Group {
            if let data = coverData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderGradient
                    .overlay(
                        Image(systemName: "book")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.white.opacity(0.5))
                    )
            }
        }
        .task {
            // Loading the full document just for the cover might be expensive
            // but for v1 it's probably okay if the cover data is small.
            if let doc = appState.libraryService.loadDocument(id: id) {
                coverData = doc.coverImageData
            }
        }
    }
}
