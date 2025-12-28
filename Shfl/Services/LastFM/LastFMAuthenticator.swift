import Foundation
import Security

struct LastFMSession: Codable, Equatable {
    let sessionKey: String
    let username: String
}

enum LastFMAuthError: Error {
    case keychainError(OSStatus)
    case authenticationFailed(String)
    case tokenExchangeFailed
}

actor LastFMAuthenticator {
    private let apiKey: String
    private let sharedSecret: String
    private let keychainService: String

    private var cachedSession: LastFMSession?

    init(
        apiKey: String,
        sharedSecret: String,
        keychainService: String = "com.shfl.lastfm.session"
    ) {
        self.apiKey = apiKey
        self.sharedSecret = sharedSecret
        self.keychainService = keychainService
    }

    var isAuthenticated: Bool {
        storedSession() != nil
    }

    func storedSession() -> LastFMSession? {
        if let cached = cachedSession {
            return cached
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(LastFMSession.self, from: data) else {
            return nil
        }

        cachedSession = session
        return session
    }

    func storeSession(_ session: LastFMSession) throws {
        let data = try JSONEncoder().encode(session)

        // Delete existing first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LastFMAuthError.keychainError(status)
        }

        cachedSession = session
    }

    func clearSession() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LastFMAuthError.keychainError(status)
        }

        cachedSession = nil
    }
}
