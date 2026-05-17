import SwiftUI

struct MiniPlayerView: View {
    @Environment(AppState.self) private var appState
    private var player: PlayerService { appState.playerService }

    var body: some View {
        guard let book = player.book else { return AnyView(EmptyView()) }
        let chapter = book.chapters[player.chapterIdx]

        return AnyView(
            Button { appState.showPlayer = true } label: {
                HStack(spacing: 12) {
                    // Cover thumbnail
                    CoverImageView(slug: book.slug, filename: book.cover)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    // Title + chapter
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Text(chapter.title)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Controls
                    HStack(spacing: 4) {
                        Button {
                            player.skip(seconds: -30)
                        } label: {
                            Image(systemName: "gobackward.30")
                                .font(.title3)
                                .foregroundStyle(.primary)
                                .padding(8)
                        }

                        Button {
                            player.togglePlay()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .contentTransition(.symbolEffect(.replace))
                                .padding(8)
                        }

                        Button {
                            player.skip(seconds: 30)
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.title3)
                                .foregroundStyle(.primary)
                                .padding(8)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    // Thin progress line at bottom
                    GeometryReader { geo in
                        let pct = player.duration > 0 ? player.currentTime / player.duration : 0
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.7))
                            .frame(width: geo.size.width * pct, height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                )
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        )
    }
}
