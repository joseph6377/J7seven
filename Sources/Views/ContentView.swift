import SwiftUI
import UniformTypeIdentifiers

enum AppTab {
    case library
    case importHub
    case voices
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    
    // Global Routing State
    @State private var selectedTab: AppTab = .library
    
    // Shared Import States
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

    // State for Proximity Magnification Tab Bar
    @State private var dragX: CGFloat? = nil
    @State private var dragY: CGFloat? = nil
    @State private var isDragging = false
    @State private var actualTabBarWidth: CGFloat = 340

    var body: some View {
        let palette = ThemePalette.resolve(appState.selectedReadingTheme, system: colorScheme)
        return ZStack(alignment: .bottom) {
            NavigationStack {
                Group {
                    switch selectedTab {
                    case .library:
                        LibraryView()
                    case .importHub:
                        ImportView(
                            onUploadTap: { showFilePicker = true },
                            onURLTap: { showURLImport = true },
                            onWriteTextTap: { showPasteSheet = true }
                        )
                    case .voices:
                        VoicesView(isLocked: false, showDoneButton: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: appState.activeSession != nil && !appState.showPlayer ? 120 : 64)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appState.activeSession != nil && !appState.showPlayer)
            }
            
            // Floating UI Overlay Container: Mini Player & Premium Dock Pill Tab Bar
            VStack(spacing: 4) {
                Spacer()
                
                if appState.activeSession != nil && !appState.showPlayer {
                    MiniPlayerView()
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                dockPillTabBar
                    .padding(.horizontal, 12)
            }
            .padding(.bottom, 14)
            .ignoresSafeArea(edges: .bottom)
            .ignoresSafeArea(.keyboard)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.activeSession != nil && !appState.showPlayer)
        .fullScreenCover(isPresented: Bindable(appState).showPlayer) {
            if let session = appState.activeSession {
                AudioPlayerView(session: session)
                    .environment(appState)
                    .preferredColorScheme(.light)
            }
        }
        .onOpenURL { url in
            print("[ContentView] Received open URL scheme: \(url.absoluteString)")
            if (url.scheme == "lysnbox" || url.scheme == "j7") && url.host == "import" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                   let queryItem = components.queryItems?.first(where: { $0.name == "id" }),
                   let payloadId = queryItem.value {
                    
                    let autoplay = components.queryItems?.first(where: { $0.name == "autoplay" })?.value == "1"
                    
                    do {
                        let payload = try SharedContainer.read(id: payloadId)
                        SharedContainer.delete(id: payloadId)
                        
                        // Dismiss player and pause any active playback to allow the import progress sheet to present immediately
                        appState.activeSession?.pause()
                        appState.showPlayer = false
                        
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
                    
                    // Dismiss player and pause any active playback to allow the import progress sheet to present immediately
                    appState.activeSession?.pause()
                    appState.showPlayer = false
                    
                    urlToImport = IdentifiableURL(url: targetURL)
                }
            } else if url.isFileURL {
                // Dismiss player and pause any active playback to allow the import progress sheet to present immediately
                appState.activeSession?.pause()
                appState.showPlayer = false
                
                Task { @MainActor in
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    await importBook(url: url)
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
            .preferredColorScheme(.light)
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
            .preferredColorScheme(.light)
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
            .preferredColorScheme(.light)
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
            .preferredColorScheme(.light)
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
            .preferredColorScheme(.light)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showPasteSheet) {
            PasteTextSheet { saved in
                let entry = LibraryEntry(from: saved)
                appState.openDocument(entry)
                appState.activeSession?.play()
            }
            .preferredColorScheme(.light)
        }
        // No longer using bottom sheet drawer for import
        .preferredColorScheme(.light)
        .environment(\.palette, palette)
    }
    
    // MARK: - Subviews
    
    private var dockPillTabBar: some View {
        HStack(spacing: 0) {
            tabBarSlot(index: 0, title: "Library", icon: "TabLibraryIcon", isSystemIcon: false, tab: .library)
            
            tabBarSlot(index: 1, title: "Import", icon: selectedTab == .importHub ? "plus.circle.fill" : "plus.circle", isSystemIcon: true, tab: .importHub)
            
            tabBarSlot(index: 2, title: "Voices", icon: "TabVoicesIcon", isSystemIcon: false, tab: .voices)
        }
        .frame(height: 64)
        .background(
            ZStack {
                // Sliding Active Tab Background (Distinct Contrast Capsule)
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: (actualTabBarWidth / 3.0) - 20, height: 48)
                    .offset(x: selectedTab == .library ? -actualTabBarWidth / 3.0 : (selectedTab == .importHub ? 0 : actualTabBarWidth / 3.0))
                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: selectedTab)
            }
        )
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.24), .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.0
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
        .shadow(color: Color.black.opacity(0.04), radius: 24, x: 0, y: 12)
        .frame(maxWidth: 500)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        actualTabBarWidth = geo.size.width
                    }
                    .onChange(of: geo.size.width) { _, newWidth in
                        actualTabBarWidth = newWidth
                    }
            }
        )
        .gesture(tabGesture)
    }
    
    private func tabBarSlot(index: Int, title: String, icon: String, isSystemIcon: Bool, tab: AppTab) -> some View {
        let scale = scaleForSlot(index)
        
        return VStack(spacing: 3) {
            if isSystemIcon {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 24, height: 24)
            } else {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
            
            Text(title)
                .font(.j7CaptionBold)
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(scale)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: scale)
        .contentShape(Rectangle())
    }
    
    // MARK: - Magnification & Gestures
    
    private var tabGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                dragX = value.location.x
                dragY = value.location.y
            }
            .onEnded { value in
                if let x = dragX, let y = dragY {
                    let verticalOffset = abs(y - 33)
                    if verticalOffset <= 55 {
                        let slotIndex = Int(round((x / actualTabBarWidth) * 3.0 - 0.5))
                        triggerSlot(min(max(slotIndex, 0), 2))
                    }
                }
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isDragging = false
                    dragX = nil
                    dragY = nil
                }
            }
    }
    
    private func scaleForSlot(_ index: Int) -> CGFloat {
        guard isDragging, let x = dragX, let y = dragY else { return 1.0 }
        if abs(y - 33) > 55 { return 1.0 }
        
        let slotCenter = actualTabBarWidth * CGFloat(2 * index + 1) / 6.0
        let distance = abs(slotCenter - x)
        
        let maxBoost: CGFloat = 0.28
        let widthFactor: CGFloat = 60.0
        return 1.0 + maxBoost * exp(-pow(distance, 2) / (2 * pow(widthFactor, 2)))
    }
    
    private func triggerSlot(_ index: Int) {
        switch index {
        case 0:
            if selectedTab != .library {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    selectedTab = .library
                }
            }
        case 1:
            if selectedTab != .importHub {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    selectedTab = .importHub
                }
            }
        case 2:
            if selectedTab != .voices {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    selectedTab = .voices
                }
            }
        default:
            break
        }
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
                        ChapterText.withSpokenTitle(index: idx, title: ch.title, paragraphs: ch.paragraphs)
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
                        ChapterText.withSpokenTitle(index: idx, title: ch.title, paragraphs: ch.paragraphs)
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
