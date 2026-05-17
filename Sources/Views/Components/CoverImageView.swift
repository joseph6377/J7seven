import SwiftUI

struct CoverImageView: View {
    let slug: String
    let filename: String?

    private var image: UIImage? {
        guard let filename else { return nil }
        return UIImage(contentsOfFile: BookPaths.localURL(slug: slug, filename: filename).path)
    }

    // Deterministic gradient per book based on slug
    private var placeholderGradient: LinearGradient {
        let hash = abs(slug.hashValue)
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
        if let img = image {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            placeholderGradient
                .overlay(
                    Image(systemName: "headphones")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                )
        }
    }
}
