import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    
    enum Tab {
        case library
        case importView
        case voices
    }
    
    @State private var selectedTab: Tab = .library
    @State private var showFilePicker = false
    @State private var showModelDownload = false
    @State private var pendingImportURL: URL?
    @State private var importErrorMessage = ""
    @State private var showImportError = false

    var body: some View {
        Group {
            switch selectedTab {
            case .library:
                NavigationStack {
                    LibraryView()
                }
            case .importView:
                ImportView(onUploadTap: {
                    showFilePicker = true
                })
            case .voices:
                VoicesView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if appState.activeSession != nil && !appState.showPlayer {
                    MiniPlayerView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                customTabBar
                    .padding(.bottom, 6)
            }
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 0.5),
                alignment: .top
            )
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.activeSession != nil && !appState.showPlayer)
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
        .fullScreenCover(isPresented: Bindable(appState).showPlayer) {
            if let session = appState.activeSession {
                AudioPlayerView(session: session)
                    .environment(appState)
                    .preferredColorScheme(appState.selectedAppearance.colorScheme)
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
        .preferredColorScheme(appState.selectedAppearance.colorScheme)
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
    }

    // Bespoke Docked Bottom Navigation Bar with Serif Typography and Haptics
    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabButton(tab: .library, title: "Library", systemImage: "books.vertical.fill")
            tabButton(tab: .importView, title: "Import Hub", systemImage: "arrow.up.circle.fill")
            tabButton(tab: .voices, title: "Voices", systemImage: "waveform.circle.fill")
        }
        .padding(.top, 10)
        .padding(.horizontal, 8)
    }

    private func tabButton(tab: Tab, title: String, systemImage: String) -> some View {
        Button {
            if selectedTab != tab {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTab = tab
                }
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary.opacity(0.35))
                    .symbolEffect(.bounce, value: selectedTab == tab)
                    .scaleEffect(selectedTab == tab ? 1.12 : 1.0)
                
                Text(title)
                    .font(.system(size: 10, weight: selectedTab == tab ? .bold : .medium, design: .serif))
                    .foregroundStyle(selectedTab == tab ? Color.primary : Color.primary.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            selectedTab = .library
            appState.openDocument(LibraryEntry(from: doc))
        } catch {
            print("[Import] Error: \(error)")
            self.importErrorMessage = error.localizedDescription
            self.showImportError = true
        }
    }
}
