import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showTTSImport = false
    @State private var pendingEpubURL: URL? = nil

    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showTTSImport = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 34, height: 34)
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            }
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if appState.ttsGenerationService.isActive {
                TTSProgressBanner(service: appState.ttsGenerationService)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.ttsGenerationService.isActive)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
