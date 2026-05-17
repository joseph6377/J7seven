import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @Namespace private var ns

    var body: some View {
        Group {
            if appState.books.isEmpty {
                emptyState
            } else {
                bookGrid
            }
        }
        .onAppear { appState.refresh() }
        .onChange(of: appState.ttsGenerationService.state) { _, newState in
            if case .done = newState { appState.refresh() }
        }
    }

    // MARK: - Grid

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(appState.books) { book in
                    NavigationLink {
                        BookDetailView(entry: book)
                    } label: {
                        BookGridCell(book: book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            appState.libraryService.deleteBook(slug: book.slug)
                            appState.refresh()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 140, height: 140)
                Circle()
                    .fill(Color.accentColor.opacity(0.05))
                    .frame(width: 190, height: 190)
                Image(systemName: "headphones")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }
            .padding(.bottom, 28)

            Text("Your Library is Empty")
                .font(.title2.bold())
                .padding(.bottom, 8)

            Text("Import an EPUB to generate your first\non-device audiobook.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Book grid cell

private struct BookGridCell: View {
    let book: LibraryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover
            CoverImageView(slug: book.slug, filename: book.cover)
                .aspectRatio(2/3, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)

            // Title + author
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.footnote.bold())
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Book detail (chapter list → player)

struct BookDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var manifest: BookManifest?
    @State private var showPlayer = false
    let entry: LibraryEntry

    private var player: PlayerService { appState.playerService }

    var body: some View {
        Group {
            if let manifest {
                chapterList(manifest: manifest)
            } else {
                ProgressView()
                    .task {
                        manifest = appState.libraryService.manifest(slug: entry.slug)
                    }
            }
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
                .environment(appState)
        }
    }

    private func chapterList(manifest: BookManifest) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header(manifest: manifest)
                    .padding(.bottom, 8)

                Divider()

                ForEach(Array(manifest.chapters.enumerated()), id: \.element.id) { idx, ch in
                    ChapterRow(
                        index: idx,
                        chapter: ch,
                        isCurrent: player.book?.slug == manifest.slug && player.chapterIdx == idx,
                        isPlaying: player.isPlaying && player.book?.slug == manifest.slug && player.chapterIdx == idx
                    ) {
                        let progress = appState.libraryService.loadProgress(slug: manifest.slug)
                        let startTime = (player.book?.slug == manifest.slug && player.chapterIdx == idx)
                            ? progress.time : 0
                        appState.playerService.play(book: manifest, chapterIdx: idx, time: startTime)
                        showPlayer = true
                    }

                    if idx < manifest.chapters.count - 1 {
                        Divider().padding(.leading, 72)
                    }
                }

                Spacer(minLength: 100)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.book != nil {
                Button { showPlayer = true } label: { MiniPlayerBar() }
                    .buttonStyle(.plain)
                    .environment(appState)
            }
        }
    }

    private func header(manifest: BookManifest) -> some View {
        VStack(spacing: 16) {
            CoverImageView(slug: manifest.slug, filename: manifest.cover)
                .frame(width: 148, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 10)
                .padding(.top, 24)

            VStack(spacing: 4) {
                Text(manifest.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text(manifest.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(manifest.chapters.count) chapters · \(manifest.duration.formattedDurationLong)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 24)

            let progress = appState.libraryService.loadProgress(slug: manifest.slug)
            let hasProgress = progress.chapterIdx > 0 || progress.time > 5

            if hasProgress {
                HStack(spacing: 10) {
                    Button {
                        appState.playerService.play(book: manifest, chapterIdx: progress.chapterIdx, time: progress.time)
                        showPlayer = true
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)

                    Button {
                        appState.playerService.play(book: manifest, chapterIdx: 0, time: 0)
                        showPlayer = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline.bold())
                            .padding(.vertical, 13)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
            } else {
                Button {
                    appState.playerService.play(book: manifest, chapterIdx: 0, time: 0)
                    showPlayer = true
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Chapter row

private struct ChapterRow: View {
    let index: Int
    let chapter: Chapter
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? Color.accentColor : Color(.secondarySystemBackground))
                        .frame(width: 40, height: 40)
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.footnote.bold())
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative)
                    } else if isCurrent {
                        Image(systemName: "pause.fill")
                            .font(.footnote.bold())
                            .foregroundStyle(.white)
                    } else {
                        Text("\(index + 1)")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.title)
                        .font(.body)
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                        .lineLimit(2)
                    Text(chapter.duration.formattedDurationLong)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mini player bar

private struct MiniPlayerBar: View {
    @Environment(AppState.self) private var appState
    private var player: PlayerService { appState.playerService }

    var body: some View {
        guard let book = player.book else { return AnyView(EmptyView()) }
        let ch = book.chapters[player.chapterIdx]

        return AnyView(
            HStack(spacing: 12) {
                CoverImageView(slug: book.slug, filename: book.cover)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(ch.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(book.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }

                Image(systemName: "chevron.up")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    let pct = player.duration > 0 ? player.currentTime / player.duration : 0
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: geo.size.width * pct, height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 2)
            }
        )
    }
}
