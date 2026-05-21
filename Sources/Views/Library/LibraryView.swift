import SwiftUI

enum LibraryFilter: String, CaseIterable {
    case shelf = "All Books"
    case favorites = "Favorites"
}


struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFilter: LibraryFilter = .shelf
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var showModelDownload = false
    @State private var isGridView = true
    @State private var favorites: Set<UUID> = Set()
    @State private var showStats = false
    
    // File Import States for 2026 standards
    @State private var showFilePicker = false
    @State private var pendingImportURL: URL?
    @State private var importErrorMessage = ""
    @State private var showImportError = false

    // Computed list of books filtered by search query
    private var filteredBooks: [LibraryEntry] {
        let books = appState.books
        if searchText.isEmpty {
            return books
        } else {
            return books.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.author?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }

    private var favoritedBooks: [LibraryEntry] {
        filteredBooks.filter { favorites.contains($0.id) }
    }

    private var historyBooks: [LibraryEntry] {
        filteredBooks.sorted(by: { $0.lastOpenedAt > $1.lastOpenedAt })
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if isSearchActive {
                    searchField
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Stats Pill & Toggleable Stats Dashboard (2026 Standards)
                        HStack {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showStats.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("⚡️")
                                        .font(.caption)
                                    Text("4.8h read")
                                        .font(.system(size: 11, weight: .bold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .rotationEffect(.degrees(showStats ? 180 : 0))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(showStats ? 0.15 : 0.08), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                        
                        if showStats {
                            statsDashboard
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Filter chips matching the new editorial style
                        filterChipsSection

                        // Content area
                        Group {
                            switch selectedFilter {
                            case .shelf:
                                if filteredBooks.isEmpty {
                                    if !searchText.isEmpty {
                                        noResultsState
                                    } else {
                                        emptyState
                                    }
                                } else {
                                    bookContent(for: filteredBooks)
                                }
                            case .favorites:
                                if favoritedBooks.isEmpty {
                                    favoritesEmptyState
                                } else {
                                    bookContent(for: favoritedBooks)
                                }
                            }
                        }
                    }
                }
            }
            
            // Premium Floating Action Button for importing books
            floatingImportButton
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
        .onAppear {
            appState.refresh()
            loadFavorites()
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            ToolbarItem(placement: .primaryAction) {
                toolbarActions
            }
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.epub],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        await importEpub(url: url)
                    }
                }
            }
        }
        .sheet(isPresented: $showModelDownload) {
            ModelDownloadView(
                synthesizer: appState.supertonicSynthesizer,
                onReady: {
                    appState.selectedEngine = .supertonic
                    if let url = pendingImportURL {
                        Task { await importEpub(url: url); pendingImportURL = nil }
                    }
                },
                onQuickStart: {
                    appState.selectedEngine = .apple
                    if let url = pendingImportURL {
                        Task { await importEpub(url: url); pendingImportURL = nil }
                    }
                }
            )
            .preferredColorScheme(appState.selectedAppearance.colorScheme)
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                TextField("Search audiobooks...", text: $searchText)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05), in: Capsule())
            
            Button("Cancel") {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isSearchActive = false
                    searchText = ""
                }
            }
            .font(.subheadline.bold())
            .foregroundStyle(Color.primary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var statsDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good evening, Joseph")
                        .font(.system(.title3, design: .serif).bold())
                        .foregroundStyle(.primary)
                    Text("Welcome to your sanctuary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption)
                    Text("4.8h read")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(appState.books.count)")
                        .font(.title2.bold())
                    Text("Books on shelf")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("100% Offline")
                        .font(.title2.bold())
                    Text("On-device AI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var filterChipsSection: some View {
        HStack(spacing: 0) {
            ForEach(LibraryFilter.allCases, id: \.self) { filter in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            selectedFilter == filter ? 
                            Color.primary.opacity(0.06) : Color.clear
                        )
                        .foregroundStyle(selectedFilter == filter ? Color.primary : Color.primary.opacity(0.4))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.02), in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.05), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var toolbarActions: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isSearchActive.toggle()
                    if !isSearchActive {
                        searchText = ""
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                    .background(isSearchActive ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)

            Menu {
                Picker("Appearance", selection: Bindable(appState).selectedAppearance) {
                    ForEach(AppAppearance.allCases) { appAppearance in
                        Label(appAppearance.rawValue, systemImage: appAppearance.iconName)
                            .tag(appAppearance)
                    }
                }
            } label: {
                Image(systemName: appState.selectedAppearance.iconName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            Menu {
                Section("Speech Engine") {
                    Picker("Engine", selection: Bindable(appState).selectedEngine) {
                        ForEach(TTSEngine.allCases) { engine in
                            Text(engine.displayName)
                                .tag(engine)
                        }
                    }
                }

                if case .notDownloaded = appState.supertonicSynthesizer.modelState {
                    Button {
                        showModelDownload = true
                    } label: {
                        Label("Download Supertonic Model", systemImage: "arrow.down.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var shelfHeader: some View {
        HStack {
            Text(selectedFilter.rawValue)
                .font(.system(.subheadline, design: .serif).bold())
                .foregroundStyle(.primary)
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isGridView.toggle()
                }
            } label: {
                Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.04), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func bookContent(for books: [LibraryEntry]) -> some View {
        VStack(spacing: 0) {
            shelfHeader
            
            if isGridView {
                gridShelf(for: books)
            } else {
                bookList(for: books)
            }
        }
    }

    @ViewBuilder
    private func gridShelf(for books: [LibraryEntry]) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 24),
            GridItem(.flexible(), spacing: 24)
        ], spacing: 28) {
            ForEach(books) { entry in
                Button {
                    appState.openDocument(entry)
                } label: {
                    VStack(spacing: 10) {
                        CoverImageView(id: entry.id)
                            .frame(width: 140, height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 5)
                        
                        VStack(spacing: 4) {
                            Text(entry.title)
                                .font(.system(size: 14, weight: .bold, design: .serif))
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                            
                            if let author = entry.author {
                                Text(author)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    favoriteButton(id: entry.id)
                    
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
        .padding(.top, 12)
        .padding(.bottom, 120)
    }

    @ViewBuilder
    private func bookList(for books: [LibraryEntry]) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(books) { entry in
                Button {
                    appState.openDocument(entry)
                } label: {
                    BookRowCell(entry: entry)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    favoriteButton(id: entry.id)
                    
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

    @ViewBuilder
    private func favoriteButton(id: UUID) -> some View {
        Button {
            toggleFavorite(id)
        } label: {
            if favorites.contains(id) {
                Label("Remove Favorite", systemImage: "star.slash")
            } else {
                Label("Add to Favorites", systemImage: "star.fill")
            }
        }
    }

    // MARK: - Helpers

    private func loadFavorites() {
        let saved = UserDefaults.standard.string(forKey: "library.favorites") ?? ""
        favorites = Set(saved.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private func toggleFavorite(_ id: UUID) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
        let savedString = favorites.map { $0.uuidString }.joined(separator: ",")
        UserDefaults.standard.set(savedString, forKey: "library.favorites")
    }

    // MARK: - Empty States

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
                .font(.system(.title3, design: .serif).bold())
                .padding(.bottom, 8)

            Text("Import an EPUB to start reading aloud.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer()
            Spacer()
        }
        .frame(minHeight: 450)
    }

    private var noResultsState: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.bottom, 20)

            Text("No Results Found")
                .font(.system(.title3, design: .serif).bold())
                .padding(.bottom, 8)

            Text("We couldn't find any audiobooks matching \"\(searchText)\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .lineSpacing(3)

            Spacer()
            Spacer()
        }
        .frame(minHeight: 450)
    }

    private var favoritesEmptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 140, height: 140)
                Circle()
                    .fill(Color.accentColor.opacity(0.05))
                    .frame(width: 190, height: 190)
                Image(systemName: "star")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }
            .padding(.bottom, 28)

            Text("No Favorites Yet")
                .font(.system(.title3, design: .serif).bold())
                .padding(.bottom, 8)

            Text("Star your favorite books in the menu to access them quickly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .lineSpacing(3)

            Spacer()
            Spacer()
        }
        .frame(minHeight: 450)
    }

    private var floatingImportButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showFilePicker = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(color: Color.accentColor.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.bottom, appState.activeSession != nil && !appState.showPlayer ? 88 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.activeSession != nil && !appState.showPlayer)
    }

    private func importEpub(url: URL) async {
        if appState.selectedEngine == .supertonic,
           case .notDownloaded = appState.supertonicSynthesizer.modelState {
            pendingImportURL = url
            showModelDownload = true
            return
        }
        
        do {
            let parsed = try EpubTextParser.parse(epubURL: url)
            let doc = SavedDocument(
                id: UUID(),
                title: parsed.title,
                author: parsed.author,
                coverImageData: parsed.coverData,
                importedAt: Date(),
                lastOpenedAt: Date(),
                chapters: parsed.chapters.enumerated().map { idx, ch in
                    ChapterText(index: idx, title: ch.title, paragraphs: ch.paragraphs)
                },
                cursor: PlaybackCursor()
            )
            appState.libraryService.saveDocument(doc)
            appState.refresh()
            appState.openDocument(LibraryEntry(from: doc))
        } catch {
            print("[Import] Error: \(error)")
            self.importErrorMessage = error.localizedDescription
            self.showImportError = true
        }
    }
}

// MARK: - Book Row Cell

private struct BookRowCell: View {
    @Environment(AppState.self) private var appState
    let entry: LibraryEntry

    var body: some View {
        HStack(spacing: 16) {
            CoverImageView(id: entry.id)
                .frame(width: 72, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                if let author = entry.author {
                    Text(author)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(entry.title)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 2)

                let progressPercent = Int(round(entry.progress * 100))
                
                HStack(spacing: 6) {
                    // Small custom micro-circular progress indicator
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 2)
                            .frame(width: 12, height: 12)
                        Circle()
                            .trim(from: 0, to: entry.progress)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 12, height: 12)
                            .rotationEffect(.degrees(-90))
                    }
                    
                    Text("\(progressPercent)% • \(entry.estimatedTimeLeft)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
