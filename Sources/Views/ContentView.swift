import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showFilePicker = false
    @State private var showModelDownload = false
    @State private var pendingImportURL: URL?

    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationTitle("J7seven")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showFilePicker = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if appState.activeSession != nil && !appState.showPlayer {
                MiniPlayerView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
            }
        }
        .sheet(isPresented: $showModelDownload) {
            ModelDownloadView(synthesizer: appState.synthesizer) {
                if let url = pendingImportURL {
                    Task {
                        await importEpub(url: url)
                        pendingImportURL = nil
                    }
                }
            }
        }
    }

    private func importEpub(url: URL) async {
        // Check model state first
        if case .notDownloaded = appState.synthesizer.modelState {
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
        }
    }
}
