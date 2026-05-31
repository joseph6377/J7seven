import UIKit
import SwiftUI
import UniformTypeIdentifiers

enum ShareError: Error {
    case noPayload
    case unsupportedPayload
    case extractionFailed(Error)
}

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    
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
              let provider = attachments.first else {
            complete(error: .noPayload)
            return
        }
        
        extractPayload(from: provider) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
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
                case .failure(let error):
                    self.complete(error: .extractionFailed(error))
                }
            }
        }
    }
    
    private func extractPayload(from provider: NSItemProvider, completion: @escaping @Sendable (Result<SharedPayload, Error>) -> Void) {
        let propertyListType = UTType.propertyList.identifier
        let urlType = UTType.url.identifier
        
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
        } else {
            completion(.failure(ShareError.unsupportedPayload))
        }
    }
    
    @MainActor
    private func openHostApp(payloadId: String) {
        let url = URL(string: "lysnbox://import?id=\(payloadId)&autoplay=1")!
        // Walk responder chain to find UIApplication (extensions can't access it directly)
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.perform(#selector(UIApplication.open(_:options:completionHandler:)), with: url, with: nil)
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
