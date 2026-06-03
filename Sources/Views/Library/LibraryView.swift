import SwiftUI
import UniformTypeIdentifiers

enum LibraryTab {
    case all
    case byType
    case favorites
}


struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: LibraryTab = .all
    @State private var activeTypeFilter: SourceFormat? = nil
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var showModelDownload = false
    @AppStorage("library.isGridView") private var isGridView = false
    @State private var favorites: Set<UUID> = Set()
    
    @State private var pendingImportURL: URL?
    @State private var pendingEntry: LibraryEntry? = nil
    @State private var showAboutSheet = false
    @State private var showWelcomeDownload = false
    @State private var showOnboardingCarousel = false

    // True only once the premium voice model is fully downloaded and ready.
    // The download affordances persist through downloading/error/cancelled states
    // so the user can always resume; they disappear only when the model is ready.
    private var isModelDownloaded: Bool {
        if case .ready = appState.supertonicSynthesizer.modelState { return true }
        return false
    }

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
            Color.j7AppBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if isSearchActive {
                    searchField
                }

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // Section 1: Top Sanctuary Greetings & Dynamic Cockpit
                        if !isSearchActive {
                            quickResumeCockpit
                        }
                        
                        // Section 2: Shelf Pinned Header & Book Lists
                        Section {
                            Group {
                                switch selectedTab {
                                case .all:
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
                                case .byType:
                                    if let formatFilter = activeTypeFilter {
                                        let formatFilteredBooks = filteredBooks.filter { $0.format == formatFilter }
                                        VStack(spacing: 0) {
                                            // Category drill-down title header with back button
                                            HStack {
                                                Button {
                                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                                        activeTypeFilter = nil
                                                    }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "chevron.left")
                                                        Text("Categories")
                                                    }
                                                    .font(.j7SubheadlineSemibold)
                                                    .foregroundStyle(Color.accentColor)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(Color.accentColor.opacity(0.08), in: Capsule())
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Spacer()
                                                
                                                Text(categoryTitle(for: formatFilter))
                                                    .font(.j7SubheadlineSerifBold)
                                                    .foregroundStyle(.primary)
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.top, 8)
                                            .padding(.bottom, 4)
                                            
                                            if formatFilteredBooks.isEmpty {
                                                emptyCategoryState(for: formatFilter)
                                            } else {
                                                bookContent(for: formatFilteredBooks)
                                            }
                                        }
                                    } else {
                                        categoryListSection
                                    }
                                }
                            }
                        } header: {
                            filterChipsSection
                        }

                        libraryFooter
                    }
                }
            }
            
        }
        .onAppear {
            appState.refresh()
            loadFavorites()
            
            if !ProcessInfo.processInfo.arguments.contains("-SkipOnboarding") {
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
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if #available(iOS 26.0, *) {
                logoToolbarItem
                    .sharedBackgroundVisibility(.hidden)
            } else {
                logoToolbarItem
            }
            ToolbarItem(placement: .primaryAction) {
                toolbarActions
            }
        }
        .sheet(isPresented: $showModelDownload, onDismiss: {
            pendingEntry = nil
        }) {
            ModelDownloadView(
                synthesizer: appState.supertonicSynthesizer,
                onReady: {
                    appState.selectedEngine = .supertonic
                    if let entry = pendingEntry {
                        appState.openDocument(entry)
                        pendingEntry = nil
                    }
                },
                onQuickStart: {
                    appState.selectedEngine = .apple
                    if let entry = pendingEntry {
                        appState.openDocument(entry)
                        pendingEntry = nil
                    }
                }
            )
            .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutView()
                .presentationDetents([.medium])
                .preferredColorScheme(.light)
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
            .preferredColorScheme(.light)
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
                .preferredColorScheme(.light)
        }
    }

    // MARK: - Subviews

    private var logoToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            AppLogoView()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.j7SubheadlineSemibold)
                    .foregroundStyle(.secondary)
                
                TextField("Search your library...", text: $searchText)
                    .font(.j7Subheadline)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFieldFocused)

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

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isSearchActive = false
                    searchText = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.j7SubheadlineBold)
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
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

    private var mostRecentBook: LibraryEntry? {
        appState.books.sorted(by: { $0.lastOpenedAt > $1.lastOpenedAt }).first
    }

    private var quickResumeCockpit: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Greeting & Sanctuary title
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(.j7Title3Serif)
                        .foregroundStyle(.primary)
                    Text("Welcome back to your sanctuary.")
                        .font(.j7Caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            if let recentBook = mostRecentBook {
                // Horizontal Quick-Resume Card
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    // Tap on the card details: Load document and open the full-screen player
                    if let doc = appState.libraryService.loadDocument(id: recentBook.id) {
                        appState.activeSession = ReaderSession(
                            document: doc,
                            player: appState.playerService,
                            scheduler: appState.activeScheduler,
                            libraryService: appState.libraryService
                        )
                        appState.showPlayer = true
                    }
                } label: {
                    HStack(spacing: 14) {
                        // Left: Cover Art Image
                        CoverImageView(id: recentBook.id)
                            .frame(width: 50, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                        
                        // Center-Left: Book Title, Author & Playback Progress
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recentBook.title)
                                .font(.j7SubheadlineSerifBold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            
                            if let author = recentBook.author, !author.isEmpty {
                                Text(author)
                                    .font(.j7Caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            
                            // Sleek Horizontal Progress Bar (2026 Standards)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 4)
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: geo.size.width * CGFloat(max(0.0, min(1.0, recentBook.progress))), height: 4)
                                }
                            }
                            .frame(height: 4)
                            .padding(.vertical, 2)
                            
                            // Progress bar / percentage & remaining time
                            Text("\(Int(round(recentBook.progress * 100)))% read • \(recentBook.estimatedTimeLeft)")
                                .font(.j7CaptionBold)
                                .foregroundStyle(Color.accentColor)
                        }
                        
                        Spacer()
                        
                        // Right: Disclosure indicator
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.25))
                    }
                    .padding(14)
                    .background(Color.j7Surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.j7Border, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                
                // Fine-Print Daily Reading Achievements
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.j7Caption)
                    Text(deviceFirstName.map { "\($0) has read \(appState.formattedTotalHoursRead) total" } ?? "You have read \(appState.formattedTotalHoursRead) total")
                        .font(.j7CaptionBold)
                }
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            } else {
                // Empty state card
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.accentColor)
                            .font(.j7SubheadlineSerifBold)
                        Text("Sanctuary Empty")
                            .font(.j7SubheadlineSerifBold)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    
                    Text("Your library is clean and waiting. Import a DRM-free EPUB book, PDF file, or web article below to start your listening sanctuary.")
                        .font(.j7Caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(Color.j7Surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.j7Border, lineWidth: 0.5)
                )
            }

            if !isModelDownloaded {
                voiceUpgradeNudge
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



    private var voiceUpgradeNudge: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showModelDownload = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.j7SubheadlineBold)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock studio-quality narration")
                        .font(.j7CaptionBold)
                        .foregroundStyle(.primary)
                    Text("Tap to download the premium voice (~350 MB)")
                        .font(.j7Caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.j7SubheadlineBold)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentColor.opacity(0.15), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var libraryFooter: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showAboutSheet = true
        } label: {
            VStack(spacing: 3) {
                Text("Built by Joseph Thekkekara")
                    .font(.j7Caption2Bold)
                    .foregroundStyle(.secondary.opacity(0.7))
                Text("LysnBox · 100% on-device")
                    .font(.j7Caption2)
                    .foregroundStyle(.secondary.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 24)
        .padding(.bottom, 120)
    }

    private var filterChipsSection: some View {
        HStack(spacing: 0) {
            filterButton(tab: .all, title: "All")
            filterButton(tab: .byType, title: "By Type")
            filterButton(tab: .favorites, title: "Favorites")
        }
        .padding(4)
        .background(Color.primary.opacity(0.04), in: Capsule())
        .overlay(Capsule().stroke(Color.j7Border, lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
    
    private func filterButton(tab: LibraryTab, title: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            Text(title)
                .font(.j7SubheadlineSerifBold)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(selectedTab == tab ? Color.j7Surface : Color.clear)
                        .shadow(
                            color: selectedTab == tab ? Color.black.opacity(0.08) : Color.clear,
                            radius: 3, x: 0, y: 1
                        )
                )
                .foregroundStyle(selectedTab == tab ? Color.primary : Color.primary.opacity(0.4))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var categoryListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                categoryRow(
                    title: "Web Articles",
                    count: filteredBooks.filter { $0.format == .web }.count,
                    format: .web
                )
                categoryRow(
                    title: "EPUB Books",
                    count: filteredBooks.filter { $0.format == .epub }.count,
                    format: .epub
                )
                categoryRow(
                    title: "PDF Documents",
                    count: filteredBooks.filter { $0.format == .pdf }.count,
                    format: .pdf
                )
                categoryRow(
                    title: "Pasted Text",
                    count: filteredBooks.filter { $0.format == .pastedText }.count,
                    format: .pastedText
                )
            }
            .background(Color.j7Surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.j7Border, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }
    
    private func categoryRow(title: String, count: Int, format: SourceFormat) -> some View {
        VStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeTypeFilter = format
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.j7BodyBold)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Text("\(count)")
                            .font(.j7CaptionBold)
                            .foregroundStyle(count > 0 ? Color.accentColor : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(count > 0 ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
                            )

                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.secondary.opacity(0.4))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if format != .pastedText {
                Divider()
                    .padding(.leading, 16) // Adjusted to align perfectly with clean typography margins!
                    .background(Color.j7Border)
            }
        }
    }

    private func categoryTitle(for format: SourceFormat) -> String {
        switch format {
        case .epub: return "EPUB Books"
        case .pdf: return "PDF Documents"
        case .web: return "Web Articles"
        case .pastedText: return "Pasted Text"
        }
    }

    private func categoryIcon(for format: SourceFormat) -> String {
        switch format {
        case .epub: return "book.closed.fill"
        case .pdf: return "doc.richtext.fill"
        case .web: return "globe"
        case .pastedText: return "text.quote"
        }
    }

    private func categoryColor(for format: SourceFormat) -> Color {
        Color.accentColor
    }

    private func emptyCategoryState(for format: SourceFormat) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: categoryIcon(for: format))
                .font(.system(size: 48))
                .foregroundStyle(categoryColor(for: format).opacity(0.7))
                .padding(.bottom, 8)
            Text("No \(categoryTitle(for: format))")
                .font(.j7Title3Serif)
                .foregroundStyle(.primary)
            Text("You haven't imported any items in this format yet.")
                .font(.j7Caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(minHeight: 350)
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
            }
            .buttonStyle(.plain)





            if !isModelDownloaded {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showModelDownload = true
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.j7SubheadlineBold)
                        .foregroundStyle(Color.primary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shelfHeader(for count: Int) -> some View {
        HStack {
            if selectedTab == .all {
                Text("\(count) items")
                    .font(.j7CaptionBold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
            } else if selectedTab == .favorites {
                Text("Favorites")
                    .font(.j7SubheadlineSerifBold)
                    .foregroundStyle(.primary)
            } else if selectedTab == .byType {
                Text("\(count) \(count == 1 ? "item" : "items")")
                    .font(.j7CaptionBold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
            }
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
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func bookContent(for books: [LibraryEntry]) -> some View {
        VStack(spacing: 0) {
            shelfHeader(for: books.count)
            
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
                    openOrDownload(entry)
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

                            if entry.format != .pastedText {
                                let progressPercent = Int(round(entry.progress * 100))
                                Text("\(progressPercent)% • \(entry.estimatedTimeLeft)")
                                    .font(.j7Caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("book_cell_\(entry.title)")
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
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func bookList(for books: [LibraryEntry]) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(books) { entry in
                Button {
                    openOrDownload(entry)
                } label: {
                    BookRowCell(entry: entry)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("book_cell_\(entry.title)")
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
        .padding(.bottom, 24)
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

    private func openOrDownload(_ entry: LibraryEntry) {
        if appState.selectedEngine == .supertonic,
           case .notDownloaded = appState.supertonicSynthesizer.modelState {
            pendingEntry = entry
            showModelDownload = true
        } else {
            appState.openDocument(entry)
        }
    }

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
                Image("TabLibraryIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundStyle(Color.accentColor.opacity(0.70))
            }
            .padding(.bottom, 28)

            Text("Your Library is Empty")
                .font(.j7Title3Serif)
                .padding(.bottom, 8)

            Text("Import a file, link, or text to start listening.")
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
                    if entry.format == .pastedText {
                        let words = entry.wordCount ?? 0
                        let minutes = max(1, Int(round(Double(words) / 150.0)))
                        Text("Pasted • \(words) words • ~\(minutes) min listen")
                            .font(.j7Caption)
                            .foregroundStyle(.secondary)
                    } else {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Onboarding Walkthrough Carousel

struct OnboardingCarouselView: View {
    @Binding var isPresented: Bool
    @State private var selection = 0
    
    var body: some View {
        ZStack {
            // Immersive clean background
            Color.j7AppBackground
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
                        title: "LysnBox",
                        subtitle: "Your Private Audiobook Sanctuary",
                        bodyText: "Welcome to a 100% offline, on-device reading experience. Let's take a quick 10-second tour of your library."
                    )
                    
                    // Slide 2: Import EPUBs or PDFs
                    carouselSlide(
                        tag: 1,
                        illustration: importIllustration,
                        title: "Import Your Books",
                        subtitle: "DRM-Free Ebooks & PDFs Ready For Speech",
                        bodyText: "Tap the center 'Import' button in the tab bar to import any DRM-free EPUB or PDF directly from your files."
                    )
                    
                    // Slide 3: Personalize Voices
                    carouselSlide(
                        tag: 2,
                        illustration: voicesIllustration,
                        title: "Premium Voices",
                        subtitle: "Studio Narrators Across 8 Languages",
                        bodyText: "Tap the 'Voices' button in the tab bar to preview and download premium multi-lingual offline voices."
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

// MARK: - URL Paste View (2026 Standards)

struct URLPasteView: View {
    @Binding var urlString: String
    let onImport: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Enter or paste the URL of any web article to extract its content for distraction-free offline audio playback.")
                    .font(.j7Body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .lineSpacing(4)
                
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.j7BodyBold)
                        .foregroundStyle(Color.accentColor)
                    
                    TextField("https://example.com/article", text: $urlString)
                        .font(.j7Body)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                
                Spacer()
                
                Button {
                    let cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let url = URL(string: cleaned) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onImport(url)
                    }
                } label: {
                    Text("Import Article")
                        .font(.j7BodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: Color.accentColor.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .disabled(URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - URL Import Progress View (2026 Standards)

struct URLImportProgressView: View {
    let url: URL
    var payload: SharedPayload? = nil
    let onComplete: (SavedDocument) -> Void
    let onCancel: () -> Void
    
    @Environment(AppState.self) private var appState
    @State private var progressState: ImportProgress = .fetching
    @State private var errorMessage: String? = nil
    @State private var importTask: Task<Void, Never>? = nil
    @State private var hasStarted = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if let error = errorMessage {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.08))
                        .frame(width: 80, height: 80)
                    Image(systemName: "exclamationmark.triangle")
                        .font(.j7Title2)
                        .foregroundStyle(.red)
                }
                
                Text("Import Failed")
                    .font(.j7Title3Serif)
                
                Text(error)
                    .font(.j7Subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(3)
                
                Spacer()
                
                Button("OK") {
                    onCancel()
                }
                .font(.j7BodyBold)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .buttonStyle(.plain)
                .padding(.bottom, 32)
                
            } else {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: 100, height: 100)
                    
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color.accentColor)
                }
                
                VStack(spacing: 8) {
                    Text(progressState.rawValue)
                        .font(.j7Title3Serif)
                        .contentTransition(.identity)
                    
                    Text(url.host ?? url.absoluteString)
                        .font(.j7Caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Cancel") {
                    importTask?.cancel()
                    onCancel()
                }
                .font(.j7SubheadlineBold)
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            startImport()
        }
    }
    
    private func startImport() {
        guard !hasStarted else { return }
        hasStarted = true
        
        importTask = Task {
            do {
                var htmlContent: String? = nil
                var preExtractedJsonLd: [String]? = nil
                
                if let payload = payload {
                    htmlContent = payload.renderedHtml
                    preExtractedJsonLd = payload.jsonLd
                    print("[URLImportProgressView] Using pre-rendered HTML and JSON-LD from share extension payload.")
                } else if let sharedPayload = readSharedPayload(), sharedPayload.url == url.absoluteString {
                    htmlContent = sharedPayload.html
                    print("[URLImportProgressView] Found shared paywall-bypassed HTML in App Group shared container.")
                    deleteSharedPayload()
                }
                
                let parsed = try await WebArticleImporter.importArticle(
                    from: url,
                    htmlContent: htmlContent,
                    preRenderedHtml: htmlContent,
                    preExtractedJsonLd: preExtractedJsonLd
                ) { progress in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.progressState = progress
                    }
                }
                
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
                    cursor: PlaybackCursor(),
                    sourceFormat: .web,
                    pageCount: nil,
                    sourceURL: parsed.sourceURL
                )
                
                appState.libraryService.saveDocument(doc)
                onComplete(doc)
            } catch {
                if !Task.isCancelled {
                    print("[URLImportProgressView] Error: \(error)")
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    private struct SharedImportPayload: Codable {
        let url: String
        let html: String?
    }
    
    private func readSharedPayload() -> SharedImportPayload? {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.in.josepht.booksappv2") else {
            return nil
        }
        let payloadURL = sharedContainer.appendingPathComponent("import_payload.json")
        guard let data = try? Data(contentsOf: payloadURL) else { return nil }
        return try? JSONDecoder().decode(SharedImportPayload.self, from: data)
    }
    
    private func deleteSharedPayload() {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.in.josepht.booksappv2") else {
            return
        }
        let payloadURL = sharedContainer.appendingPathComponent("import_payload.json")
        try? FileManager.default.removeItem(at: payloadURL)
    }
}

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

