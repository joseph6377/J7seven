import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    static var backgroundSessionCompletionHandler: (() -> Void)?
    
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == "in.josepht.booksappv2.modeldownload" {
            Self.backgroundSessionCompletionHandler = completionHandler
        }
    }
}

@main
struct BooksAppV2: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.light)
        }
    }
}
