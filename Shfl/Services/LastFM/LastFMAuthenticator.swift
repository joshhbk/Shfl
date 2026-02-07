import Foundation
import Security
import AuthenticationServices
import UIKit

struct LastFMSession: Codable, Equatable {
    let sessionKey: String
    let username: String
}

enum LastFMAuthError: Error {
    case keychainError(OSStatus)
    case authenticationFailed(String)
    case tokenExchangeFailed
    case cancelled
    case missingPresentationAnchor
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
        case .cancelled:
            return nil
        case .missingPresentationAnchor:
            return "No active window is available to present Last.fm sign-in. Try again once the app window is active."
        }
    }
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

    private func storeSessionAsync(_ session: LastFMSession) async throws {
        try storeSession(session)
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

    // MARK: - Web Authentication

    @MainActor
    func authenticate() async throws -> LastFMSession {
        let authURLString = "https://www.last.fm/api/auth/?api_key=\(apiKey)&cb=shfl://lastfm"
        guard let authURL = URL(string: authURLString) else {
            throw LastFMAuthError.authenticationFailed("Invalid auth URL")
        }

        let token = try await performWebAuth(url: authURL)
        let session = try await exchangeTokenForSession(token: token)
        try await storeSessionAsync(session)
        return session
    }

    @MainActor
    private func performWebAuth(url: URL) async throws -> String {
        guard WebAuthContextProvider.shared.currentPresentationAnchor() != nil else {
            throw LastFMAuthError.missingPresentationAnchor
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "shfl"
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: LastFMAuthError.cancelled)
                    return
                }

                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
                    continuation.resume(throwing: LastFMAuthError.authenticationFailed("No token in callback"))
                    return
                }

                continuation.resume(returning: token)
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = WebAuthContextProvider.shared
            guard session.start() else {
                continuation.resume(throwing: LastFMAuthError.authenticationFailed("Unable to start Last.fm sign-in. Please try again."))
                return
            }
        }
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

        let (data, _) = try await URLSession.shared.data(from: url)

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

// MARK: - Presentation Context

@MainActor
final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthContextProvider()

    private override init() {
        super.init()
    }

    func currentPresentationAnchor() -> ASPresentationAnchor? {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { lhs, rhs in
                lhs.activationState.sortPriority < rhs.activationState.sortPriority
            }

        for scene in windowScenes {
            if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let visibleWindow = scene.windows.first(where: { !$0.isHidden }) {
                return visibleWindow
            }
            if let anyWindow = scene.windows.first {
                return anyWindow
            }
        }

        return nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        currentPresentationAnchor() ?? ASPresentationAnchor()
    }
}

private extension UIScene.ActivationState {
    var sortPriority: Int {
        switch self {
        case .foregroundActive:
            return 0
        case .foregroundInactive:
            return 1
        case .background:
            return 2
        case .unattached:
            return 3
        @unknown default:
            return 4
        }
    }
}
