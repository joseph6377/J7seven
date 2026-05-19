import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.books.isEmpty {
                emptyState
            } else {
                bookGrid
            }
        }
        .onAppear { appState.refresh() }
    }

    // MARK: - Grid

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(appState.books) { entry in
                    Button {
                        appState.openDocument(entry)
                    } label: {
                        BookGridCell(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            appState.libraryService.deleteDocument(id: entry.id)
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
                Image(systemName: "book.closed")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }
            .padding(.bottom, 28)

            Text("Your Library is Empty")
                .font(.title2.bold())
                .padding(.bottom, 8)

            Text("Import an EPUB to start reading aloud.")
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
    @Environment(AppState.self) private var appState
    let entry: LibraryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                // We'll need a way to load the cover data from the SavedDocument
                // For the grid cell, maybe we should have a CoverImage component that takes an ID
                CoverImageView(id: entry.id)
                    .aspectRatio(2/3, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.footnote.bold())
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if let author = entry.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(entry.lastOpenedAt.formattedRelative())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

extension Date {
    func formattedRelative() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Opened " + formatter.localizedString(for: self, relativeTo: Date())
    }
}
