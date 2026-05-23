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
    private var isBuffering: Bool { session.isBuffering }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Info Section: Tap cover & labels to expand full player
                Button {
                    appState.showPlayer = true
                } label: {
                    HStack(spacing: 10) {
                        CoverImageView(id: session.document.id)
                            .frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.document.title)
                                .font(.j7SubheadlineSerifBold)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            
                            Text(session.document.chapters[session.currentChapterIndex].title)
                                .font(.j7CaptionMedium)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(session.document.title)")

                Spacer()

                // Sleek, minimal transport controls
                HStack(spacing: 14) {
                    // Rewind 30s
                    Button {
                        session.skip(seconds: -30)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "gobackward.30")
                            .font(.j7BodyMedium)
                            .foregroundStyle(Color.primary.opacity(0.75))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rewind 30 seconds")

                    // Play/Pause — shows spinner overlay while synthesizing
                    Button {
                        session.togglePlay()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        ZStack {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.j7BodyBold)
                                .contentTransition(.symbolEffect(.replace))
                                .opacity(isBuffering ? 0.3 : 1)
                            
                            if isBuffering {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.primary)
                                    .scaleEffect(0.85)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(Color.primary.opacity(0.04), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")

                    // Skip 30s
                    Button {
                        session.skip(seconds: 30)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.j7BodyMedium)
                            .foregroundStyle(Color.primary.opacity(0.75))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip 30 seconds")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Premium Liquid Glass bottom progress bar clipped to corner radius
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.08))
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * overallProgress))
                        .animation(.linear(duration: 0.35), value: overallProgress)
                }
            }
            .frame(height: 3.5)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 15, x: 0, y: 5)
        .accessibilityElement(children: .contain)
    }
}
