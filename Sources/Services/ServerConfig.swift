import Foundation

/// Server connection settings: URL + Basic Auth credentials.
/// Username + password live in the Keychain; URL lives in UserDefaults so the
/// app can show "you haven't set this up yet" without unlocking the keychain.
struct ServerConfig: Equatable {
    var baseURL: String
    var username: String
    var password: String

    var isUsable: Bool {
        URL(string: baseURL) != nil && !username.isEmpty && !password.isEmpty
    }

    var basicAuthHeader: String? {
        let raw = "\(username):\(password)"
        guard let data = raw.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    /// Resolve a path against `baseURL`, tolerating trailing/leading slashes.
    func url(forPath path: String) -> URL? {
        guard let base = URL(string: baseURL) else { return nil }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(trimmed)
    }
}

enum ServerConfigStore {
    private enum Key {
        static let baseURL  = "server.baseURL"
        static let username = "server.username"
        static let password = "server.password"
    }

    static func load() -> ServerConfig {
        ServerConfig(
            baseURL:  UserDefaults.standard.string(forKey: Key.baseURL) ?? "https://books.josepht.in",
            username: Keychain.string(account: Key.username) ?? "",
            password: Keychain.string(account: Key.password) ?? ""
        )
    }

    static func save(_ config: ServerConfig) {
        UserDefaults.standard.set(config.baseURL, forKey: Key.baseURL)
        Keychain.setString(config.username, account: Key.username)
        Keychain.setString(config.password, account: Key.password)
    }
}
