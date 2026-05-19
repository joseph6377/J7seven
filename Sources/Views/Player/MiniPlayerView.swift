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

    // Overall book progress by paragraph count
    private var overallProgress: Double {
        let totalParagraphs = session.document.chapters.reduce(0) { $0 + $1.paragraphs.count }
        guard totalParagraphs > 0 else { return 0 }
        let before = session.document.chapters
            .prefix(session.currentChapterIndex)
            .reduce(0) { $0 + $1.paragraphs.count }
        return Double(before + session.currentParagraphIndex) / Double(totalParagraphs)
    }

    private var isPlaying: Bool { session.state == .playing }
    private var isSynthesizing: Bool { session.state == .synthesizing }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Tap cover + info to expand full player
                Button {
                    appState.showPlayer = true
                } label: {
                    HStack(spacing: 12) {
                        CoverImageView(id: session.document.id)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.document.title)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Text(session.document.chapters[session.currentChapterIndex].title)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(session.document.title)")

                // Play / pause — shows spinner overlay while synthesizing
                Button {
                    session.togglePlay()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .contentTransition(.symbolEffect(.replace))
                            .opacity(isSynthesizing ? 0.3 : 1)
                        if isSynthesizing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                        }
                    }
                    .frame(width: 52, height: 52)
                }
                .foregroundStyle(.primary)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Overall progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: max(0, geo.size.width * overallProgress))
                        .animation(.linear(duration: 0.3), value: overallProgress)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }
}
