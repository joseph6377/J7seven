import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.books.isEmpty {
                emptyState
            } else {
                bookList
            }
        }
        .onAppear { appState.refresh() }
        // Refresh library when a TTS book finishes generating
        .onChange(of: appState.ttsGenerationService.state) { _, newState in
            if case .done = newState { appState.refresh() }
        }
    }

    // MARK: - Book list

    private var bookList: some View {
        List(appState.books) { book in
            NavigationLink {
                BookPlayerLink(entry: book)
            } label: {
                BookRow(book: book)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    appState.libraryService.deleteBook(slug: book.slug)
                    appState.refresh()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("No Books Yet")
                .font(.title2.bold())
            Text("Tap **+** to import an EPUB and generate an audiobook.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Book detail (chapter list → player)

private struct BookPlayerLink: View {
    @Environment(AppState.self) private var appState
    let entry: LibraryEntry

    var body: some View {
        BookDetailView(entry: entry)
    }
}

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
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
                .environment(appState)
        }
    }

    private func chapterList(manifest: BookManifest) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Cover + metadata header
                header(manifest: manifest)
                    .padding(.bottom, 8)

                Divider()

                // Chapter rows
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
            }
        }
        // Mini-player at bottom if something is already loaded
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.book != nil {
                Button { showPlayer = true } label: { MiniPlayerBar() }
                    .buttonStyle(.plain)
                    .environment(appState)
            }
        }
    }

    private func header(manifest: BookManifest) -> some View {
        VStack(spacing: 12) {
            CoverImageView(slug: manifest.slug, filename: manifest.cover)
                .frame(width: 140, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
                .padding(.top, 20)

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
            }
            .padding(.horizontal, 24)

            // Resume / Play from start
            HStack(spacing: 12) {
                let progress = appState.libraryService.loadProgress(slug: manifest.slug)
                let hasProgress = progress.chapterIdx > 0 || progress.time > 5

                if hasProgress {
                    Button {
                        appState.playerService.play(book: manifest, chapterIdx: progress.chapterIdx, time: progress.time)
                        showPlayer = true
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)

                    Button {
                        appState.playerService.play(book: manifest, chapterIdx: 0, time: 0)
                        showPlayer = true
                    } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        appState.playerService.play(book: manifest, chapterIdx: 0, time: 0)
                        showPlayer = true
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }
            }
            .padding(.horizontal, 24)
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
                // Number / playing indicator
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
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
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

// MARK: - Mini player bar (shown at bottom of chapter list)

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
                // Thin progress line
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

// MARK: - Book row

private struct BookRow: View {
    let book: LibraryEntry

    var body: some View {
        HStack(spacing: 12) {
            // Cover
            CoverImageView(slug: book.slug, filename: book.cover)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(book.duration.formattedDurationLong)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
