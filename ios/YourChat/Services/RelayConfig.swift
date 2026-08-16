import Foundation
import Observation
import Security

/// Small Keychain wrapper. The relay token is the one credential the app holds,
/// and a shipped build must not keep it in UserDefaults or in the binary.
enum Keychain {
    private static let service = "dev.meravin.chat.relay"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ account: String, _ value: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        var insert = base
        insert[kSecValueData as String] = Data(value.utf8)
        // Available after first unlock so a background reconnect still works,
        // but never syncs to iCloud or another device.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Where the relay is and how to authenticate to it. Settings can change the
/// host at runtime; the compiled `Secrets` values are only the first-run
/// defaults so a fresh install works without a setup screen.
@MainActor
@Observable
final class RelayConfig {
    private enum Keys {
        static let host = "relay.host"
        static let tls = "relay.useTLS"
        static let token = "relay.token"
    }

    private let defaults: UserDefaults

    var host: String {
        didSet { defaults.set(host, forKey: Keys.host) }
    }

    var useTLS: Bool {
        didSet { defaults.set(useTLS, forKey: Keys.tls) }
    }

    var token: String {
        didSet { Keychain.write(Keys.token, token) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        host = defaults.string(forKey: Keys.host) ?? Secrets.relayHost
        useTLS = defaults.object(forKey: Keys.tls) as? Bool ?? Secrets.useTLS

        if let stored = Keychain.read(Keys.token) {
            token = stored
        } else {
            // First launch: migrate the compiled default into the Keychain once.
            token = Secrets.appToken
            Keychain.write(Keys.token, Secrets.appToken)
        }
    }

    var apiBaseURL: URL {
        URL(string: "\(useTLS ? "https" : "http")://\(host)")!
    }

    var webSocketURL: URL {
        URL(string: "\(useTLS ? "wss" : "ws")://\(host)/ws")!
    }

    var isConfigured: Bool {
        !token.isEmpty && token != "replace-with-the-relay-token" && !host.isEmpty
    }

    func authorize(_ request: inout URLRequest) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}
