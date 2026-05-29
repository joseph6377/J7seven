import Foundation
import WebKit
import SwiftSoup

@MainActor
final class HeadlessWebViewFetcher: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var navigationTimer: Timer?
    
    func fetchHTML(from url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/605.1.15"
            self.webView = webView
            
            // Timeout after 20 seconds
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await self?.fail(with: URLError(.timedOut))
            }
            
            webView.load(URLRequest(url: url))
        }
    }
    
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Wait for 800ms idle after load completes
            self.navigationTimer?.invalidate()
            self.navigationTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.extractHTML()
                }
            }
        }
    }
    
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.fail(with: error)
        }
    }
    
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.fail(with: error)
        }
    }
    
    private func extractHTML() {
        guard let webView = webView else { return }
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            Task { @MainActor in
                if let error = error {
                    self?.fail(with: error)
                } else if let html = result as? String {
                    self?.succeed(with: html)
                } else {
                    self?.fail(with: URLError(.cannotParseResponse))
                }
            }
        }
    }
    
    private func succeed(with html: String) {
        timeoutTask?.cancel()
        navigationTimer?.invalidate()
        continuation?.resume(returning: html)
        cleanup()
    }
    
    private func fail(with error: Error) {
        timeoutTask?.cancel()
        navigationTimer?.invalidate()
        continuation?.resume(throwing: error)
        cleanup()
    }
    
    private func cleanup() {
        continuation = nil
        webView = nil
        timeoutTask = nil
        navigationTimer = nil
    }
}

enum HtmlFetcher {
    
    /// realistic Safari User Agent matching iOS Safari on iPhone
    static let safariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/605.1.15"
    
    static func fetch(url: URL) async throws -> String {
        // Stage 1: Try plain fetch
        print("[HtmlFetcher] Attempting plain URLSession fetch...")
        var plainHtml: String?
        do {
            plainHtml = try await fetchPlain(url: url)
        } catch {
            print("[HtmlFetcher] Plain URLSession fetch failed: \(error). Falling back to headless web view.")
        }
        
        if let html = plainHtml {
            // Check heuristic
            if !isSPA(html: html) {
                print("[HtmlFetcher] Plain fetch successful. Content conforms to Static HTML.")
                return html
            } else {
                print("[HtmlFetcher] SPA Heuristic triggered. Content requires headless rendering.")
            }
        }
        
        // Stage 2: Headless render fallback
        print("[HtmlFetcher] Executing headless WKWebView rendering...")
        let fetcher = await HeadlessWebViewFetcher()
        return try await fetcher.fetchHTML(from: url)
    }
    
    static func fetchPlain(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        request.setValue(safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        return html
    }
    
    static func isSPA(html: String) -> Bool {
        do {
            let doc = try SwiftSoup.parse(html)
            
            // 1. <body> text length < 500 chars
            if let body = doc.body() {
                let bodyText = try body.text()
                if bodyText.count < 500 {
                    return true
                }
            }
            
            // 2. No <article>, no <main>, no JSON-LD AND
            // <head> contains React/Next/Vue/Nuxt/Svelte/Angular fingerprints
            let hasArticle = try !doc.select("article").isEmpty
            let hasMain = try !doc.select("main").isEmpty
            let hasJsonLd = try !doc.select("script[type=application/ld+json]").isEmpty
            
            if !hasArticle && !hasMain && !hasJsonLd {
                if let head = doc.head() {
                    let headHtml = try head.outerHtml().lowercased()
                    let spaFingerprints = ["react", "_next/static", "vue", "nuxt", "svelte", "ng-version", "ng-app"]
                    for fingerprint in spaFingerprints {
                        if headHtml.contains(fingerprint) {
                            return true
                        }
                    }
                }
            }
        } catch {
            // Treat parse failures as normal content so we don't block
        }
        
        return false
    }
}
