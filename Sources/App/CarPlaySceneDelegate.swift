import Combine
import CarPlay
import MediaPlayer

/// Bridges CarPlay's template UI to the existing playback stack (`AppState` /
/// `ReaderSession` / `PlayerService`). Now Playing screen is driven entirely by
/// `PlayerService.updateNowPlaying` via `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`,
/// which CarPlay already reads from — so no separate now-playing wiring is needed here.
@MainActor
final class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    /// Rows of the chapter list currently on the template stack, kept so the "now playing"
    /// marker can follow the session instead of freezing at whatever was playing when the
    /// list was built.
    private var chapterItems: [(chapterIndex: Int, item: CPListItem)] = []
    private var chapterSubscription: AnyCancellable?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(makeLibraryTemplate(), animated: true, completion: nil)

        if AppState.shared.activeSession != nil {
            // Build a sensible back stack: Library → Chapters → Now Playing.
            showChapters()
            showNowPlaying()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        chapterSubscription = nil
        chapterItems = []
    }

    private func makeLibraryTemplate() -> CPListTemplate {
        let appState = AppState.shared
        appState.refresh()

        let items = appState.books.map { entry -> CPListItem in
            let item = CPListItem(text: entry.title, detailText: entry.author ?? entry.estimatedTimeLeft)
            item.handler = { [weak self] _, completion in
                appState.openDocument(entry)
                self?.showChapters()
                completion()
            }
            return item
        }

        return CPListTemplate(title: "Library", sections: [CPListSection(items: items)])
    }

    /// Pushes a list of the active book's chapters. Tapping one jumps playback
    /// there via `ReaderSession.jumpToChapter` and opens Now Playing.
    private func showChapters() {
        guard let interfaceController, let session = AppState.shared.activeSession else { return }

        let chapters = session.document.chapters
        let currentIndex = session.currentChapterIndex
        // CarPlay caps how many rows a list template may show.
        let maxItems = CPListTemplate.maximumItemCount
        var rows: [(chapterIndex: Int, item: CPListItem)] = []
        let items = chapters.prefix(maxItems).map { chapter -> CPListItem in
            let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let item = CPListItem(
                text: title.isEmpty ? "Chapter \(chapter.index + 1)" : title,
                detailText: nil
            )
            item.isPlaying = chapter.index == currentIndex
            item.handler = { [weak self] _, completion in
                session.jumpToChapter(chapter.index)
                session.play()
                self?.showNowPlaying()
                completion()
            }
            rows.append((chapter.index, item))
            return item
        }

        chapterItems = rows
        chapterSubscription = session.$currentChapterIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] index in self?.updatePlayingChapter(index) }

        let template = CPListTemplate(title: session.document.title, sections: [CPListSection(items: items)])
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func updatePlayingChapter(_ currentIndex: Int) {
        for row in chapterItems {
            row.item.isPlaying = row.chapterIndex == currentIndex
        }
    }

    private func showNowPlaying() {
        guard let interfaceController else { return }
        interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }
}
