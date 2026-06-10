import UIKit
import SwiftUI
import UniformTypeIdentifiers

struct SendableItemProvider: @unchecked Sendable {
    let provider: NSItemProvider
}

enum ShareError: Error {
    case noPayload
    case unsupportedPayload
    case extractionFailed(Error)
}

@objc private protocol URLOpener {
    @discardableResult
    func openURL(_ url: URL) -> Bool
}

@objc private protocol UIApplicationOpenURL {
    @objc(openURL:options:completionHandler:)
    func openURL(_ url: URL, options: [String: Any], completionHandler completion: ((Bool) -> Void)?)
}

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var attachmentsToProcess: [NSItemProvider] = []
    private var currentAttachmentIndex: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processSharedItem()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        activityIndicator.startAnimating()
    }
    
    private func processSharedItem() {
        if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.in.josepht.booksappv2") {
            let logURL = sharedContainer.appendingPathComponent("debug-log.txt")
            try? FileManager.default.removeItem(at: logURL)
        }
        ShareViewController.logDebug("--- Started processing shared item ---")
        
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments,
              !attachments.isEmpty else {
            complete(error: .noPayload)
            return
        }
        
        self.attachmentsToProcess = attachments
        self.currentAttachmentIndex = 0
        processCurrentAttachment()
    }
    
    private func processCurrentAttachment() {
        guard currentAttachmentIndex < attachmentsToProcess.count else {
            complete(error: .noPayload)
            return
        }
        
        let provider = attachmentsToProcess[currentAttachmentIndex]
        extractPayload(from: provider) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let payload):
                    let payloadId = UUID().uuidString
                    do {
                        try SharedContainer.write(payload, id: payloadId)
                        self.openHostApp(payloadId: payloadId)
                    } catch {
                        self.complete(error: .extractionFailed(error))
                    }
                case .failure:
                    self.currentAttachmentIndex += 1
                    self.processCurrentAttachment()
                }
            }
        }
    }
    
    private func extractPayload(from provider: NSItemProvider, completion: @escaping @Sendable (Result<SharedPayload, Error>) -> Void) {
        let sendableProvider = SendableItemProvider(provider: provider)
        ShareViewController.extractPropertyList(from: sendableProvider.provider) { result in
            switch result {
            case .success(let payload):
                completion(.success(payload))
            case .failure:
                ShareViewController.extractDocumentsOrURL(from: sendableProvider.provider) { result in
                    switch result {
                    case .success(let payload):
                        completion(.success(payload))
                    case .failure:
                        ShareViewController.extractText(from: sendableProvider.provider, completion: completion)
                    }
                }
            }
        }
    }
    
    nonisolated static private func extractPropertyList(from provider: NSItemProvider, completion: @escaping @Sendable (Result<SharedPayload, Error>) -> Void) {
        let propertyListType = UTType.propertyList.identifier
        guard provider.hasItemConformingToTypeIdentifier(propertyListType) else {
            completion(.failure(ShareError.unsupportedPayload))
            return
        }
        
        provider.loadItem(forTypeIdentifier: propertyListType, options: nil) { item, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            var parsedPayload: SharedPayload? = nil
            if let dict = item as? NSDictionary,
               let js = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any],
               let urlString = js["url"] as? String,
               let url = URL(string: urlString) {
                
                let title = js["title"] as? String
                let html = js["html"] as? String
                let jsonLd = js["jsonLd"] as? [String]
                
                parsedPayload = SharedPayload(
                    url: url,
                    title: title,
                    renderedHtml: html,
                    jsonLd: jsonLd
                )
            }
            
            if let payload = parsedPayload {
                completion(.success(payload))
            } else {
                completion(.failure(ShareError.unsupportedPayload))
            }
        }
    }
    
    nonisolated static private func extractDocumentsOrURL(from provider: NSItemProvider, completion: @escaping @Sendable (Result<SharedPayload, Error>) -> Void) {
        let pdfType = UTType.pdf.identifier
        let epubType = UTType.epub.identifier
        let fileURLType = UTType.fileURL.identifier
        let urlType = UTType.url.identifier
        
        let hasPDF = provider.hasItemConformingToTypeIdentifier(pdfType)
        let hasEPUB = provider.hasItemConformingToTypeIdentifier(epubType)
        let hasFileURL = provider.hasItemConformingToTypeIdentifier(fileURLType)
        let hasURL = provider.hasItemConformingToTypeIdentifier(urlType)
        
        guard hasPDF || hasEPUB || hasFileURL || hasURL else {
            completion(.failure(ShareError.unsupportedPayload))
            return
        }
        
        let matchedType = hasPDF ? pdfType : (hasEPUB ? epubType : (hasFileURL ? fileURLType : urlType))
        
        provider.loadItem(forTypeIdentifier: matchedType, options: nil) { item, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            var parsedPayload: SharedPayload? = nil
            var urlValue: URL? = nil
            
            if let url = item as? URL {
                urlValue = url
            } else if let urlString = item as? String {
                urlValue = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            
            if let url = urlValue {
                if url.isFileURL {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    
                    do {
                        let sharedFileURL = try ShareViewController.copyFileToSharedContainer(from: url)
                        parsedPayload = SharedPayload(url: sharedFileURL, title: url.lastPathComponent, renderedHtml: nil, jsonLd: nil)
                    } catch {
                        print("[ShareViewController] Error copying file: \(error)")
                    }
                } else {
                    parsedPayload = SharedPayload(url: url, title: nil, renderedHtml: nil, jsonLd: nil)
                }
            }
            
            if let payload = parsedPayload {
                completion(.success(payload))
            } else {
                completion(.failure(ShareError.unsupportedPayload))
            }
        }
    }
    
    nonisolated static private func extractText(from provider: NSItemProvider, completion: @escaping @Sendable (Result<SharedPayload, Error>) -> Void) {
        let textType = UTType.text.identifier
        guard provider.hasItemConformingToTypeIdentifier(textType) else {
            completion(.failure(ShareError.unsupportedPayload))
            return
        }
        
        provider.loadItem(forTypeIdentifier: textType, options: nil) { item, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            var parsedPayload: SharedPayload? = nil
            if let text = item as? String,
               let url = ShareViewController.extractURL(from: text) {
                parsedPayload = SharedPayload(url: url, title: nil, renderedHtml: nil, jsonLd: nil)
            }
            
            if let payload = parsedPayload {
                completion(.success(payload))
            } else {
                completion(.failure(ShareError.unsupportedPayload))
            }
        }
    }
    
    nonisolated static private func copyFileToSharedContainer(from sourceURL: URL) throws -> URL {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.in.josepht.booksappv2") else {
            throw ShareError.unsupportedPayload
        }
        
        let destinationDirectory = sharedContainer.appendingPathComponent("SharedFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        
        let fileName = sourceURL.lastPathComponent
        let destinationURL = destinationDirectory.appendingPathComponent(fileName)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
    
    nonisolated static private func extractURL(from text: String) -> URL? {
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil {
            return url
        }
        
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            if let url = match.url {
                return url
            }
        }
        return nil
    }
    @MainActor
    private func openHostApp(payloadId: String) {
        let url = URL(string: "lysnbox://import?id=\(payloadId)&autoplay=1")!
        ShareViewController.logDebug("openHostApp triggered with payloadId: \(payloadId)")
        
        // 1. Try public extensionContext.open first
        if let context = self.extensionContext {
            ShareViewController.logDebug("Calling public extensionContext.open...")
            context.open(url, completionHandler: { [weak self] success in
                ShareViewController.logDebug("Public open callback. Success: \(success)")
                if success {
                    Task { @MainActor in
                        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    }
                } else {
                    Task { @MainActor in
                        // If public open fails, sequentially try private selectors
                        let selectors = ["openURL:completionHandler:", "openURL:completion:", "_openURL:completion:"]
                        self?.tryPrivateExtensionOpen(url: url, selectors: selectors, index: 0)
                    }
                }
            })
        } else {
            ShareViewController.logDebug("extensionContext is nil. Trying fallback...")
            tryFallbackOpen(url: url)
        }
    }
    
    @MainActor
    private func tryPrivateExtensionOpen(url: URL, selectors: [String], index: Int) {
        guard index < selectors.count else {
            ShareViewController.logDebug("All private extensionContext selectors failed/exhausted. Trying fallback...")
            tryFallbackOpen(url: url)
            return
        }
        
        let selectorName = selectors[index]
        guard let context = self.extensionContext else {
            ShareViewController.logDebug("extensionContext is nil. Trying fallback...")
            tryFallbackOpen(url: url)
            return
        }
        
        let sel = NSSelectorFromString(selectorName)
        guard context.responds(to: sel) else {
            ShareViewController.logDebug("Context does not respond to \(selectorName). Trying next private selector...")
            tryPrivateExtensionOpen(url: url, selectors: selectors, index: index + 1)
            return
        }
        
        ShareViewController.logDebug("Performing private selector \(selectorName) on extensionContext...")
        let nsUrl = url as NSURL
        
        // We'll also use a local flag to make sure we don't proceed twice (e.g. if completion block is called after timeout)
        var hasCompleted = false
        
        // Define completion handler block
        let completion: @convention(block) (Bool) -> Void = { [weak self] success in
            ShareViewController.logDebug("Private selector \(selectorName) callback success: \(success)")
            Task { @MainActor in
                guard !hasCompleted else { return }
                hasCompleted = true
                
                if success {
                    ShareViewController.logDebug("URL opened successfully via \(selectorName), completing request.")
                    self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                } else {
                    self?.tryPrivateExtensionOpen(url: url, selectors: selectors, index: index + 1)
                }
            }
        }
        
        context.perform(sel, with: nsUrl, with: completion as AnyObject)
        
        // Schedule a 0.5s safety timeout just in case the selector is called but ignores/never executes the completion block
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor in
                guard !hasCompleted else { return }
                ShareViewController.logDebug("Private selector \(selectorName) timed out after 0.5s. Trying next private selector...")
                hasCompleted = true
                self?.tryPrivateExtensionOpen(url: url, selectors: selectors, index: index + 1)
            }
        }
    }
    
    @MainActor
    private func tryFallbackOpen(url: URL) {
        ShareViewController.logDebug("tryFallbackOpen triggered")
        
        // 1. Try dynamic UIApplication sharedApplication lookup and call openURL:options:completionHandler:
        if let appClass = NSClassFromString("UIApplication") as? NSObject.Type {
            let sharedSelector = NSSelectorFromString("sharedApplication")
            if appClass.responds(to: sharedSelector),
               let sharedApp = appClass.perform(sharedSelector)?.takeUnretainedValue() {
                ShareViewController.logDebug("Found UIApplication.sharedApplication dynamically")
                
                let sharedAppAny = sharedApp as AnyObject
                var hasCompleted = false
                
                let completion: @convention(block) (Bool) -> Void = { [weak self] success in
                    ShareViewController.logDebug("UIApplication openURL success: \(success)")
                    Task { @MainActor in
                        guard !hasCompleted else { return }
                        hasCompleted = true
                        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    }
                }
                
                // Call using dynamic AnyObject dispatch mapping to openURL:options:completionHandler:
                sharedAppAny.openURL(url, options: [:], completionHandler: completion)
                
                // Schedule 0.5s safety timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    Task { @MainActor in
                        guard !hasCompleted else { return }
                        ShareViewController.logDebug("UIApplication openURL timed out after 0.5s. Completing request anyway.")
                        hasCompleted = true
                        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    }
                }
                return
            }
        }
        
        // 2. Try walking the responder chain for legacy openURL: selector
        let openURLSelector = #selector(URLOpener.openURL(_:))
        var responder: UIResponder? = self
        while let r = responder {
            ShareViewController.logDebug("Checking responder for legacy openURL:: \(type(of: r))")
            if r.responds(to: openURLSelector) {
                ShareViewController.logDebug("Found responder responding to legacy openURL:: \(type(of: r)), performing...")
                r.perform(openURLSelector, with: url)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
                return
            }
            responder = r.next
        }
        
        ShareViewController.logDebug("All open methods failed. Completing request anyway.")
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
    
    @MainActor
    private func complete(error: ShareError) {
        ShareViewController.logDebug("complete triggered with error: \(error)")
        activityIndicator.stopAnimating()
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
    
    nonisolated static private func logDebug(_ message: String) {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.in.josepht.booksappv2") else {
            return
        }
        let logURL = sharedContainer.appendingPathComponent("debug-log.txt")
        let formattedMessage = "\(Date()): \(message)\n"
        if let data = formattedMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
