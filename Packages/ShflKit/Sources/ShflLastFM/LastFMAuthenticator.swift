import Foundation
import Security

package nonisolated struct LastFMSession: Codable, Equatable, Sendable {
    let sessionKey: String
    let username: String
}

/// Where the listener approves Shfl, and the URL scheme Last.fm redirects to
/// afterwards. Run it in a web authentication session that watches for
/// `callbackURLScheme`.
public nonisolated struct LastFMSignIn: Equatable, Sendable {
    public let url: URL
    public let callbackURLScheme: String
}

enum LastFMAuthError: Error {
    case keychainError(OSStatus)
    case authenticationFailed(String)
    case tokenExchangeFailed
}

extension LastFMAuthError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .keychainError:
            return "Unable to securely store Last.fm session."
        case let .authenticationFailed(message):
            return message
        case .tokenExchangeFailed:
            return "Unable to complete Last.fm sign-in."
        }
    }
}

/// Run signIn() in a web authentication session, then pass the redirect URL to completeSignIn(callbackURL:).
actor LastFMAuthenticator {
    typealias Fetch = @Sendable (URL) async throws -> Data

    private nonisolated static let callbackURLScheme = "shfl"

    private let apiKey: String
    private let sharedSecret: String
    private let keychainService: String
    private let fetch: Fetch

    private var cachedSession: LastFMSession?

    init(
        apiKey: String,
        sharedSecret: String,
        keychainService: String = "com.shfl.lastfm.session",
        fetch: @escaping Fetch = { try await URLSession.shared.data(from: $0).0 }
    ) {
        self.apiKey = apiKey
        self.sharedSecret = sharedSecret
        self.keychainService = keychainService
        self.fetch = fetch
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

    // MARK: - Sign-in

    nonisolated func signIn() throws -> LastFMSignIn {
        let authURLString = "https://www.last.fm/api/auth/?api_key=\(apiKey)&cb=\(Self.callbackURLScheme)://lastfm"
        guard let authURL = URL(string: authURLString) else {
            throw LastFMAuthError.authenticationFailed("Invalid auth URL")
        }
        return LastFMSignIn(url: authURL, callbackURLScheme: Self.callbackURLScheme)
    }

    func completeSignIn(callbackURL: URL) async throws -> LastFMSession {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            throw LastFMAuthError.authenticationFailed("No token in callback")
        }

        let session = try await exchangeTokenForSession(token: token)
        try storeSession(session)
        return session
    }

    nonisolated private func exchangeTokenForSession(token: String) async throws -> LastFMSession {
        var params: [String: String] = [
            "method": "auth.getSession",
            "api_key": apiKey,
            "token": token
        ]

        let signature = LastFMClient.generateSignature(params: params, secret: sharedSecret)
        params["api_sig"] = signature
        params["format"] = "json"

        let queryString = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")

        guard let url = URL(string: "https://ws.audioscrobbler.com/2.0/?\(queryString)") else {
            throw LastFMAuthError.tokenExchangeFailed
        }

        let data = try await fetch(url)

        struct SessionResponse: Decodable {
            let session: SessionData

            struct SessionData: Decodable {
                let name: String
                let key: String
            }
        }

        do {
            let response = try JSONDecoder().decode(SessionResponse.self, from: data)
            return LastFMSession(sessionKey: response.session.key, username: response.session.name)
        } catch {
            throw LastFMAuthError.tokenExchangeFailed
        }
    }
}
