import SwiftUI

struct MiniPlayerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.activeSession {
            MiniPlayerContent(session: session)
        }
    }
}

private struct MiniPlayerContent: View {
    @Environment(AppState.self) private var appState
    @ObservedObject var session: ReaderSession

    var body: some View {
        let chapter = session.document.chapters[session.currentChapterIndex]
        Button { appState.showPlayer = true } label: {
            HStack(spacing: 12) {
                CoverImageView(id: session.document.id)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.document.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text(chapter.title)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    session.togglePlay()
                } label: {
                    Image(systemName: session.state == .playing ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}
