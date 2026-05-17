import SwiftUI

struct CoverImageView: View {
    let slug: String
    let filename: String?

    private var image: UIImage? {
        guard let filename else { return nil }
        return UIImage(contentsOfFile: BookPaths.localURL(slug: slug, filename: filename).path)
    }

    var body: some View {
        if let img = image {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [Color(.systemGray4), Color(.systemGray5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.4))
            )
        }
    }
}
