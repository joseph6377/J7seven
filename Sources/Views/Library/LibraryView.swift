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
    @State private var showAboutSheet = false
    @State private var showWelcomeDownload = false
    @State private var showVoices = false
    @State private var showOnboardingCarousel = false

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
                                        .font(.j7Caption)
                                    Text(appState.formattedTotalHoursRead)
                                        .font(.j7CaptionBold)
                                    Image(systemName: "chevron.down")
                                        .font(.j7Caption2Bold)
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
            
            // Check if user has seen welcome download prompt and model is not downloaded
            let hasSeenWelcome = UserDefaults.standard.bool(forKey: "hasSeenWelcomeDownloadPrompt")
            if !hasSeenWelcome {
                if case .notDownloaded = appState.supertonicSynthesizer.modelState {
                    showWelcomeDownload = true
                }
            } else {
                let hasSeenShowcase = UserDefaults.standard.bool(forKey: "library.onboarding.showcased")
                if !hasSeenShowcase {
                    showOnboardingCarousel = true
                }
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showAboutSheet = true
                } label: {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
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
        .sheet(isPresented: $showAboutSheet) {
            AboutView()
                .presentationDetents([.medium])
                .preferredColorScheme(appState.selectedAppearance.colorScheme)
        }
        .sheet(isPresented: $showWelcomeDownload) {
            WelcomeModelDownloadView(
                synthesizer: appState.supertonicSynthesizer,
                onReady: {
                    appState.selectedEngine = .supertonic
                    UserDefaults.standard.set(true, forKey: "hasSeenWelcomeDownloadPrompt")
                },
                onUseApple: {
                    appState.selectedEngine = .apple
                    if let firstApple = appState.appleVoiceScheduler.cachedVoices.first {
                        UserDefaults.standard.set(firstApple.id, forKey: "tts.defaultVoiceId")
                    }
                    UserDefaults.standard.set(true, forKey: "hasSeenWelcomeDownloadPrompt")
                }
            )
            .interactiveDismissDisabled()
            .preferredColorScheme(appState.selectedAppearance.colorScheme)
        }
        .sheet(isPresented: $showVoices) {
            VoicesView(isLocked: false)
                .preferredColorScheme(appState.selectedAppearance.colorScheme)
        }
        .onChange(of: showWelcomeDownload) { _, newValue in
            if !newValue {
                let hasSeenShowcase = UserDefaults.standard.bool(forKey: "library.onboarding.showcased")
                if !hasSeenShowcase {
                    showOnboardingCarousel = true
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboardingCarousel) {
            OnboardingCarouselView(isPresented: $showOnboardingCarousel)
                .preferredColorScheme(appState.selectedAppearance.colorScheme)
        }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.j7SubheadlineSemibold)
                    .foregroundStyle(.secondary)
                
                TextField("Search audiobooks...", text: $searchText)
                    .font(.j7Subheadline)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.j7Body)
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
            .font(.j7SubheadlineBold)
            .foregroundStyle(Color.primary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var deviceFirstName: String? {
        let deviceName = UIDevice.current.name
        // Device names are typically "Joseph's iPhone" or "Joseph's iPad"
        if let apostropheRange = deviceName.range(of: "'s ") ?? deviceName.range(of: "\u{2019}s ") {
            let firstName = String(deviceName[deviceName.startIndex..<apostropheRange.lowerBound])
            if !firstName.isEmpty { return firstName }
        }
        return nil
    }

    private var greetingText: String {
        if let name = deviceFirstName {
            return "\(timeOfDayGreeting), \(name)"
        }
        return timeOfDayGreeting
    }

    private var statsDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(.j7Title3Serif)
                        .foregroundStyle(.primary)
                    Text("Welcome to your sanctuary.")
                        .font(.j7Caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.j7Caption)
                    Text(appState.formattedTotalHoursRead)
                        .font(.j7CaptionBold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(appState.books.count)")
                        .font(.j7Title2)
                    Text("Books on shelf")
                        .font(.j7Caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("100% Offline")
                        .font(.j7Title2)
                    Text("On-device AI")
                        .font(.j7Caption)
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
                        .font(.j7SubheadlineSerifBold)
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
                    .font(.j7SubheadlineBold)
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                    .background(isSearchActive ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showVoices = true
            } label: {
                Image(systemName: "waveform")
                    .font(.j7SubheadlineBold)
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05), in: Circle())
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
                    .font(.j7SubheadlineBold)
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            if case .notDownloaded = appState.supertonicSynthesizer.modelState {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showModelDownload = true
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.j7SubheadlineBold)
                        .foregroundStyle(Color.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var shelfHeader: some View {
        HStack {
            Text(selectedFilter.rawValue)
                .font(.j7SubheadlineSerifBold)
                .foregroundStyle(.primary)
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isGridView.toggle()
                }
            } label: {
                Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                    .font(.j7SubheadlineBold)
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
                                .font(.j7BodySerifBold)
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                            
                            if let author = entry.author {
                                Text(author)
                                    .font(.j7Caption)
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
                    .font(.j7Hero)
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }
            .padding(.bottom, 28)

            Text("Your Library is Empty")
                .font(.j7Title3Serif)
                .padding(.bottom, 8)

            Text("Import an EPUB to start reading aloud.")
                .font(.j7Subheadline)
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
                .font(.j7Hero)
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.bottom, 20)

            Text("No Results Found")
                .font(.j7Title3Serif)
                .padding(.bottom, 8)

            Text("We couldn't find any audiobooks matching \"\(searchText)\".")
                .font(.j7Subheadline)
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
                    .font(.j7Hero)
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }
            .padding(.bottom, 28)

            Text("No Favorites Yet")
                .font(.j7Title3Serif)
                .padding(.bottom, 8)

            Text("Star your favorite books in the menu to access them quickly.")
                .font(.j7Subheadline)
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
                .font(.j7Title2)
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
                        .font(.j7CaptionMedium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(entry.title)
                    .font(.j7BodySerifBold)
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
                        .font(.j7Caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Onboarding Walkthrough Carousel

struct OnboardingCarouselView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    @State private var selection = 0
    
    private var backgroundColor: Color {
        if colorScheme == .light {
            return Color(red: 0.98, green: 0.97, blue: 0.95)
        } else {
            return Color(red: 0.05, green: 0.05, blue: 0.05)
        }
    }
    
    var body: some View {
        ZStack {
            // Immersive clean background
            backgroundColor
                .ignoresSafeArea()
            
            // Subtle ambient backdrop glow
            VStack {
                Spacer()
                Circle()
                    .fill(Color.accentColor.opacity(0.03))
                    .frame(width: 350, height: 350)
                    .blur(radius: 80)
                    .offset(y: 100)
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Bar with Skip Option
                HStack {
                    Spacer()
                    if selection < 2 {
                        Button("Skip Intro") {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        }
                        .font(.j7CaptionBold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .transition(.opacity)
                    }
                }
                .padding(.top, 16)
                .frame(height: 50)
                
                // Swipable Carousel Content
                TabView(selection: $selection) {
                    // Slide 1: Welcome to the Sanctuary
                    carouselSlide(
                        tag: 0,
                        illustration: welcomeIllustration,
                        title: "J7 Listen",
                        subtitle: "Your Private Audiobook Sanctuary",
                        bodyText: "Welcome to a 100% offline, on-device reading experience. Let's take a quick 10-second tour of your library."
                    )
                    
                    // Slide 2: Import EPUBs
                    carouselSlide(
                        tag: 1,
                        illustration: importIllustration,
                        title: "Import Your Books",
                        subtitle: "DRM-Free Ebooks Ready For Speech",
                        bodyText: "Tap the floating blue '+' button in the bottom right corner of your library to import any DRM-free EPUB directly from your files."
                    )
                    
                    // Slide 3: Personalize Voices
                    carouselSlide(
                        tag: 2,
                        illustration: voicesIllustration,
                        title: "Premium Voices",
                        subtitle: "Studio Narrators Across 8 Languages",
                        bodyText: "Tap the waveform icon in the navigation bar to preview and download premium multi-lingual offline voices."
                    )
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Bottom Control Section
                VStack(spacing: 20) {
                    // Page Indicator Dots
                    HStack(spacing: 8) {
                        ForEach(0..<3) { idx in
                            Circle()
                                .fill(selection == idx ? Color.accentColor : Color.primary.opacity(0.12))
                                .frame(width: selection == idx ? 16 : 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
                        }
                    }
                    
                    // Action Button
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if selection < 2 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selection += 1
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text(selection == 2 ? "Enter Sanctuary" : "Next")
                            .font(.j7SubheadlineBold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: Color.accentColor.opacity(0.2), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
    }
    
    private func dismiss() {
        UserDefaults.standard.set(true, forKey: "library.onboarding.showcased")
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isPresented = false
        }
    }
    
    @ViewBuilder
    private func carouselSlide(
        tag: Int,
        illustration: some View,
        title: String,
        subtitle: String,
        bodyText: String
    ) -> some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Mock illustration container
            illustration
            
            VStack(spacing: 12) {
                Text(title)
                    .font(.j7Title1Serif)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                Text(subtitle)
                    .font(.j7SubheadlineSerifBold)
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.center)
                
                Text(bodyText)
                    .font(.j7Body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
        }
        .tag(tag)
    }
    
    // MARK: - Slide Mock Illustrations
    
    private var welcomeIllustration: some View {
        ZStack {
            Circle()
                .stroke(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                .frame(width: 150, height: 150)
            
            Circle()
                .fill(Color.accentColor.opacity(0.04))
                .frame(width: 120, height: 120)
                .overlay(
                    Circle()
                        .stroke(Color.accentColor.opacity(0.15), lineWidth: 0.5)
                )
            
            Image(systemName: "headphones")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Color.accentColor)
        }
        .frame(height: 180)
    }
    
    private var importIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.02))
                .frame(width: 95, height: 135)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.secondary)
                        
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 55, height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 40, height: 4)
                        }
                    }
                )
                .rotationEffect(.degrees(-10))
                .offset(x: -24, y: -10)
            
            Circle()
                .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 56, height: 56)
                .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                )
                .offset(x: 34, y: 24)
        }
        .frame(height: 180)
    }
    
    private var voicesIllustration: some View {
        ZStack {
            HStack(spacing: 5) {
                ForEach(0..<8) { idx in
                    let heights: [CGFloat] = [20, 45, 65, 30, 75, 50, 35, 15]
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 3.5, height: heights[idx % heights.count])
                }
            }
            .scaleEffect(1.3)
            
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Text("Sofia (ES)")
                        .font(.j7CaptionBold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.03), radius: 3)
                        .offset(x: -15)
                    
                    Text("Arthur (FR)")
                        .font(.j7CaptionBold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.08), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5))
                        .offset(x: 10, y: -5)
                }
                
                Text("Hiro (JA)")
                    .font(.j7CaptionBold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.03), radius: 3)
                    .offset(x: -25)
            }
        }
        .frame(height: 180)
    }
}
