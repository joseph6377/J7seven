import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                LibraryView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Floating Mini Player (Pill-shaped capsule for 2026 Standards)
            if appState.activeSession != nil && !appState.showPlayer {
                MiniPlayerView()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24) // Float nicely above the home indicator area
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
        .preferredColorScheme(appState.selectedAppearance.colorScheme)
    }
}
