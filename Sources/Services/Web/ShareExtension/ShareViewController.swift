import UIKit
import SwiftUI
import UniformTypeIdentifiers

enum ShareError: Error {
    case noPayload
    case unsupportedPayload
    case extractionFailed(Error)
}

@objc private protocol URLOpener {
    @discardableResult
    func openURL(_ url: URL) -> Bool
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
                        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
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
        let propertyListType = UTType.propertyList.identifier
        let urlType = UTType.url.identifier
        let textType = UTType.text.identifier
        
        if provider.hasItemConformingToTypeIdentifier(propertyListType) {
            provider.loadItem(forTypeIdentifier: propertyListType, options: nil) { item, error in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
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
                
                DispatchQueue.main.async {
                    if let payload = parsedPayload {
                        completion(.success(payload))
                    } else {
                        completion(.failure(ShareError.unsupportedPayload))
                    }
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(urlType) {
            provider.loadItem(forTypeIdentifier: urlType, options: nil) { item, error in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
                
                var parsedPayload: SharedPayload? = nil
                if let url = item as? URL {
                    parsedPayload = SharedPayload(url: url, title: nil, renderedHtml: nil, jsonLd: nil)
                }
                
                DispatchQueue.main.async {
                    if let payload = parsedPayload {
                        completion(.success(payload))
                    } else {
                        completion(.failure(ShareError.unsupportedPayload))
                    }
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(textType) {
            provider.loadItem(forTypeIdentifier: textType, options: nil) { item, error in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
                
                var parsedPayload: SharedPayload? = nil
                if let text = item as? String,
                   let url = ShareViewController.extractURL(from: text) {
                    parsedPayload = SharedPayload(url: url, title: nil, renderedHtml: nil, jsonLd: nil)
                }
                
                DispatchQueue.main.async {
                    if let payload = parsedPayload {
                        completion(.success(payload))
                    } else {
                        completion(.failure(ShareError.unsupportedPayload))
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                completion(.failure(ShareError.unsupportedPayload))
            }
        }
    }
    
    static private func extractURL(from text: String) -> URL? {
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
        let openURLSelector = #selector(URLOpener.openURL(_:))
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: openURLSelector) {
                r.perform(openURLSelector, with: url)
                return
            }
            responder = r.next
        }
    }
    
    @MainActor
    private func complete(error: ShareError) {
        print("[ShareViewController] Error processing item: \(error)")
        activityIndicator.stopAnimating()
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
