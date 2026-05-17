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

// MARK: - Book player link (loads manifest + progress, then shows PlayerView)

private struct BookPlayerLink: View {
    @Environment(AppState.self) private var appState
    let entry: LibraryEntry

    var body: some View {
        Group {
            if appState.playerService.book?.slug == entry.slug {
                PlayerView()
            } else {
                ProgressView()
                    .task {
                        guard let manifest = appState.libraryService.manifest(slug: entry.slug)
                        else { return }
                        let progress = appState.libraryService.loadProgress(slug: entry.slug)
                        appState.playerService.play(
                            book: manifest,
                            chapterIdx: progress.chapterIdx,
                            time: progress.time)
                    }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Book row

private struct BookRow: View {
    let book: LibraryEntry

    var body: some View {
        HStack(spacing: 12) {
            // Cover
            CoverImageView(slug: book.slug, cover: book.cover)
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
