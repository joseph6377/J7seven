import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showTTSImport = false
    @State private var pendingEpubURL: URL? = nil

    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showTTSImport = true
                        } label: {
                            Label("Add Book", systemImage: "plus")
                        }
                    }
                }
        }
        .fileImporter(isPresented: $showTTSImport,
                      allowedContentTypes: [.epub],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                pendingEpubURL = url
            }
        }
        .sheet(item: $pendingEpubURL) { url in
            TTSImportView(epubURL: url,
                          generationService: appState.ttsGenerationService,
                          supertonicService: appState.supertonicService)
        }
        // Generation progress banner sits above tab bar
        .safeAreaInset(edge: .bottom) {
            if appState.ttsGenerationService.isActive {
                TTSProgressBanner(service: appState.ttsGenerationService) {
                    // TODO: open player for in-progress book
                }
                .padding(.bottom, 8)
            }
        }
    }
}

// Make URL identifiable for .sheet(item:)
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
