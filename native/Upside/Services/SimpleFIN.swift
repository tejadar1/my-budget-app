import Foundation
import Security

/// SimpleFIN Bridge: one connection reads every bank you've linked there.
///
/// Protocol (https://www.simplefin.org/protocol.html):
/// 1. The setup token is a base64 "claim URL". POSTing to it once returns
///    an access URL with credentials: https://user:pass@host/simplefin
/// 2. GET {access}/accounts?start-date=… returns accounts + transactions.
enum SimpleFIN {
    static let signUpURL = URL(string: "https://beta-bridge.simplefin.org/")!

    enum Failure: LocalizedError {
        case badToken, claimFailed(Int), notConnected, server(String)
        var errorDescription: String? {
            switch self {
            case .badToken: return "That doesn’t look like a SimpleFIN setup token. Copy it again from SimpleFIN."
            case .claimFailed(let code) where code == 403:
                return "That setup token was already used. Create a new one at SimpleFIN."
            case .claimFailed(let code): return "SimpleFIN didn’t accept the token (error \(code))."
            case .notConnected: return "Banks aren’t connected yet."
            case .server(let message): return message
            }
        }
    }

    /// Exchange a one-time setup token for a long-lived access URL.
    static func claim(setupToken: String) async throws -> URL {
        let cleaned = setupToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Data(base64Encoded: cleaned),
              let claimString = String(data: decoded, encoding: .utf8),
              let claimURL = URL(string: claimString.trimmingCharacters(in: .whitespacesAndNewlines)),
              claimURL.scheme == "https" else {
            throw Failure.badToken
        }
        var request = URLRequest(url: claimURL)
        request.httpMethod = "POST"
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let text = String(data: body, encoding: .utf8),
              let access = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Failure.claimFailed(status)
        }
        return access
    }

    struct AccountSet: Decodable {
        var errors: [String]?
        var accounts: [SFAccount]
    }

    struct SFAccount: Decodable {
        struct Org: Decodable {
            var name: String?
            var domain: String?
        }
        var id: String
        var name: String
        var currency: String?
        var balance: String
        var org: Org
        var transactions: [SFTransaction]?
    }

    struct SFTransaction: Decodable {
        var id: String
        var posted: Int
        var amount: String
        var description: String
        var payee: String?
        var pending: Bool?
        var transacted_at: Int?
        /// Bank-specific data. Some feeds put a category or merchant code
        /// (MCC) here; most send nothing.
        var extra: Extra?
    }

    /// Reads any text or number values from `extra`, whatever the keys.
    struct Extra: Decodable {
        var values: [String: String] = [:]

        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: Key.self) else { return }
            for key in c.allKeys {
                if let s = try? c.decode(String.self, forKey: key) { values[key.stringValue] = s }
                else if let n = try? c.decode(Int.self, forKey: key) { values[key.stringValue] = String(n) }
            }
        }

        /// "mcc:5813" for a merchant code, otherwise the category text.
        var bankCategory: String? {
            let lower = Dictionary(values.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
            for key in ["mcc", "merchant_category_code", "category_code"] {
                if let v = lower[key], Int(v) != nil { return "mcc:\(v)" }
            }
            for key in ["category", "merchant_category", "categories", "type"] {
                if let v = lower[key], !v.isEmpty { return v }
            }
            return nil
        }
    }

    /// Accounts and transactions from `since` up to `until` (now if nil).
    /// The Bridge allows at most 90 days per request.
    static func fetch(accessURL: URL, since: Date, until: Date? = nil) async throws -> AccountSet {
        // URLSession doesn't send credentials embedded in the URL; move them
        // into a Basic auth header.
        guard var parts = URLComponents(url: accessURL, resolvingAgainstBaseURL: false) else {
            throw Failure.notConnected
        }
        let user = parts.user ?? ""
        let password = parts.password ?? ""
        parts.user = nil
        parts.password = nil
        parts.path += "/accounts"
        parts.queryItems = [
            URLQueryItem(name: "start-date", value: String(Int(since.timeIntervalSince1970))),
            URLQueryItem(name: "pending", value: "1"),
        ]
        if let until {
            parts.queryItems?.append(URLQueryItem(name: "end-date", value: String(Int(until.timeIntervalSince1970))))
        }
        guard let url = parts.url else { throw Failure.notConnected }
        var request = URLRequest(url: url)
        let auth = Data("\(user):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure.server(status == 403
                ? "SimpleFIN access was revoked. Connect your banks again."
                : "SimpleFIN returned error \(status). Try again in a bit.")
        }
        return try JSONDecoder().decode(AccountSet.self, from: body)
    }
}

/// The SimpleFIN access URL is a password; keep it in the Keychain.
enum Keychain {
    private static let service = "com.tejadar1.upside"

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
