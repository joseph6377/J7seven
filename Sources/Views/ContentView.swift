import SwiftUI
import UniformTypeIdentifiers

enum AppTab {
    case library
    case voices
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    
    // Global Routing State
    @State private var selectedTab: AppTab = .library
    
    // Shared Import States
    @State private var showImportDrawer = false
    @State private var showFilePicker = false
    @State private var showURLImport = false
    @State private var showPasteSheet = false
    @State private var urlString = ""
    @State private var activeURLToImport: URL? = nil
    
    // Model Download / Error States
    @State private var showModelDownload = false
    @State private var pendingImportURL: URL? = nil
    @State private var pendingEntry: LibraryEntry? = nil
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    
    // Incoming URL Shares / extension states
    @State private var urlToImport: IdentifiableURL? = nil
    @State private var activePayload: SharedPayload? = nil
    @State private var autoplayOnComplete = false

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                Group {
                    switch selectedTab {
                    case .library:
                        LibraryView()
                    case .voices:
                        VoicesView(isLocked: false, showDoneButton: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                customTabBar
            }
            
            // Floating Mini Player docked perfectly 12 points above the custom tab bar
            if appState.activeSession != nil && !appState.showPlayer {
                VStack(spacing: 12) {
                    Spacer()
                    MiniPlayerView()
                        .padding(.horizontal, 16)
                    Color.clear
                        .frame(height: 56) // Matches height of custom tab bar content
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.activeSession != nil && !appState.showPlayer)
        .fullScreenCover(isPresented: Bindable(appState).showPlayer) {
            if let session = appState.activeSession {
                AudioPlayerView(session: session)
                    .environment(appState)
                    .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
        }
        .onOpenURL { url in
            print("[ContentView] Received open URL scheme: \(url.absoluteString)")
            if url.scheme == "j7" && url.host == "import" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                   let queryItem = components.queryItems?.first(where: { $0.name == "id" }),
                   let payloadId = queryItem.value {
                    
                    let autoplay = components.queryItems?.first(where: { $0.name == "autoplay" })?.value == "1"
                    
                    do {
                        let payload = try SharedContainer.read(id: payloadId)
                        SharedContainer.delete(id: payloadId)
                        
                        self.autoplayOnComplete = autoplay
                        self.activePayload = payload
                    } catch {
                        print("[ContentView] Error reading shared payload: \(error)")
                    }
                }
            } else if url.scheme == "booksapp" && url.host == "import" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                   let queryItem = components.queryItems?.first(where: { $0.name == "url" }),
                   let urlString = queryItem.value,
                   let targetURL = URL(string: urlString) {
                    urlToImport = IdentifiableURL(url: targetURL)
                }
            }
        }
        .sheet(item: $activePayload) { payload in
            URLImportProgressView(url: payload.url, payload: payload) { doc in
                activePayload = nil
                appState.refresh()
                appState.openDocument(LibraryEntry(from: doc))
                if autoplayOnComplete {
                    appState.activeSession?.play()
                }
            } onCancel: {
                activePayload = nil
            }
            .environment(appState)
            .preferredColorScheme(appState.selectedAppearance.colorScheme)
            .interactiveDismissDisabled()
        }
        .sheet(item: $urlToImport) { identURL in
            URLImportProgressView(url: identURL.url) { doc in
                urlToImport = nil
                appState.refresh()
                appState.openDocument(LibraryEntry(from: doc))
            } onCancel: {
                urlToImport = nil
            }
            .environment(appState)
            .preferredColorScheme(appState.selectedAppearance.colorScheme)
            .interactiveDismissDisabled()
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.epub, .pdf],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        await importBook(url: url)
                    }
                }
            }
        }
        .sheet(isPresented: $showModelDownload, onDismiss: {
            pendingEntry = nil
        }) {
            ModelDownloadView(
                synthesizer: appState.supertonicSynthesizer,
                onReady: {
                    appState.selectedEngine = .supertonic
                    if let url = pendingImportURL {
                        Task { await importBook(url: url); pendingImportURL = nil }
                    }
                    if let entry = pendingEntry {
                        appState.openDocument(entry)
                        pendingEntry = nil
                    }
                },
                onQuickStart: {
                    appState.selectedEngine = .apple
                    if let url = pendingImportURL {
                        Task { await importBook(url: url); pendingImportURL = nil }
                    }
                    if let entry = pendingEntry {
                        appState.openDocument(entry)
                        pendingEntry = nil
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
        .sheet(isPresented: $showURLImport) {
            URLPasteView(urlString: $urlString) { url in
                showURLImport = false
                urlString = ""
                activeURLToImport = url
            }
            .preferredColorScheme(appState.selectedAppearance.colorScheme)
        }
        .sheet(item: Binding(
            get: { activeURLToImport.map { IdentifiableURL(url: $0) } },
            set: { activeURLToImport = $0?.url }
        )) { identURL in
            URLImportProgressView(url: identURL.url) { doc in
                activeURLToImport = nil
                appState.refresh()
                appState.openDocument(LibraryEntry(from: doc))
            } onCancel: {
                activeURLToImport = nil
            }
            .preferredColorScheme(appState.selectedAppearance.colorScheme)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showPasteSheet) {
            PasteTextSheet { saved in
                let entry = LibraryEntry(from: saved)
                appState.openDocument(entry)
                appState.activeSession?.play()
            }
            .preferredColorScheme(appState.selectedAppearance.colorScheme)
        }
        .sheet(isPresented: $showImportDrawer) {
            ImportDrawerSheet(
                onSelectFile: { showFilePicker = true },
                onSelectURL: { showURLImport = true },
                onSelectPasteText: { showPasteSheet = true }
            )
            .presentationDetents([.fraction(0.35), .medium])
            .preferredColorScheme(appState.selectedAppearance.colorScheme)
        }
        .preferredColorScheme(appState.selectedAppearance.colorScheme)
    }
    
    // MARK: - Subviews
    
    private var customTabBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.primary.opacity(0.08))
            
            HStack {
                // Library Tab Button
                tabButton(tab: .library, title: "Library", icon: "books.vertical.fill")
                
                Spacer()
                
                // Prominent Symmetrical Center Plus Action Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showImportDrawer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .offset(y: -4)
                
                Spacer()
                
                // Voices Tab Button
                tabButton(tab: .voices, title: "Voices", icon: "waveform")
            }
            .padding(.horizontal, 48)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
    
    private func tabButton(tab: AppTab, title: String, icon: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.j7CaptionBold)
            }
            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary.opacity(0.40))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helper Methods
    
    private func importBook(url: URL) async {
        if appState.selectedEngine == .supertonic,
           case .notDownloaded = appState.supertonicSynthesizer.modelState {
            pendingImportURL = url
            showModelDownload = true
            return
        }
        
        do {
            let doc: SavedDocument
            if url.pathExtension.lowercased() == "pdf" {
                let parsed = try await PdfTextParser.parse(pdfURL: url)
                doc = SavedDocument(
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
                    sourceFormat: .pdf,
                    pageCount: parsed.pageCount
                )
            } else {
                let parsed = try EpubTextParser.parse(epubURL: url)
                doc = SavedDocument(
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
                    sourceFormat: .epub,
                    pageCount: nil
                )
            }
            appState.libraryService.saveDocument(doc)
            appState.refresh()
            appState.openDocument(LibraryEntry(from: doc))
        } catch {
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }
}
