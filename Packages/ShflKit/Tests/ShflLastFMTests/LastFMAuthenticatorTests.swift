import Foundation
import Testing
@testable import ShflLastFM

@Suite("LastFMAuthenticator Tests")
struct LastFMAuthenticatorTests {

    @Test("Store and retrieve session from keychain")
    func storeAndRetrieve() async throws {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let session = LastFMSession(sessionKey: "abc123", username: "testuser")

        // Keychain may not be available on CI - handle gracefully
        do {
            try await authenticator.storeSession(session)
        } catch {
            // Skip test if keychain not available (e.g., on CI)
            return
        }

        let retrieved = await authenticator.storedSession()
        #expect(retrieved?.sessionKey == "abc123")
        #expect(retrieved?.username == "testuser")

        // Cleanup
        try? await authenticator.clearSession()
    }

    @Test("isAuthenticated returns true when session exists")
    func isAuthenticatedTrue() async throws {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let session = LastFMSession(sessionKey: "abc123", username: "testuser")

        // Keychain may not be available on CI - handle gracefully
        do {
            try await authenticator.storeSession(session)
        } catch {
            // Skip test if keychain not available (e.g., on CI)
            return
        }

        let isAuth = await authenticator.isAuthenticated
        #expect(isAuth == true)

        // Cleanup
        try? await authenticator.clearSession()
    }

    @Test("isAuthenticated returns false when no session")
    func isAuthenticatedFalse() async {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let isAuth = await authenticator.isAuthenticated
        #expect(isAuth == false)
    }

    @Test("Clear session removes from keychain")
    func clearSession() async throws {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let session = LastFMSession(sessionKey: "abc123", username: "testuser")

        // Keychain may not be available on CI - handle gracefully
        do {
            try await authenticator.storeSession(session)
            try await authenticator.clearSession()
        } catch {
            // Skip test if keychain not available (e.g., on CI)
            return
        }

        let retrieved = await authenticator.storedSession()
        #expect(retrieved == nil)
    }

    @Test("Sign-in asks Last.fm to redirect to Shfl's callback scheme")
    func signIn() throws {
        let authenticator = LastFMAuthenticator(apiKey: "testkey", sharedSecret: "testsecret")

        let signIn = try authenticator.signIn()

        #expect(signIn.url.absoluteString == "https://www.last.fm/api/auth/?api_key=testkey&cb=shfl://lastfm")
        #expect(signIn.callbackURLScheme == "shfl")
        let callback = try #require(
            URLComponents(url: signIn.url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "cb" })?.value
        )
        #expect(URL(string: callback)?.scheme == signIn.callbackURLScheme)
    }

    @Test("Completing sign-in trades the callback token for a signed-in session")
    func completeSignInExchangesToken() async throws {
        let requests = RequestRecorder()
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)",
            fetch: { url in
                await requests.record(url)
                return Data(#"{"session":{"name":"testuser","key":"session-key","subscriber":0}}"#.utf8)
            }
        )
        let callbackURL = try #require(URL(string: "shfl://lastfm?token=callback-token"))

        let session: LastFMSession?
        do {
            session = try await authenticator.completeSignIn(callbackURL: callbackURL)
        } catch LastFMAuthError.keychainError {
            // Keychain may not be available on CI; the exchange still ran.
            session = nil
        }

        let request = try #require(await requests.urls.first)
        let components = try #require(URLComponents(url: request, resolvingAgainstBaseURL: false))
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        #expect(components.host == "ws.audioscrobbler.com")
        #expect(query["method"] == "auth.getSession")
        #expect(query["api_key"] == "testkey")
        #expect(query["token"] == "callback-token")
        #expect(query["format"] == "json")
        #expect(query["api_sig"] == LastFMClient.generateSignature(
            params: ["method": "auth.getSession", "api_key": "testkey", "token": "callback-token"],
            secret: "testsecret"
        ))

        if let session {
            #expect(session == LastFMSession(sessionKey: "session-key", username: "testuser"))
            #expect(await authenticator.storedSession() == session)
            try? await authenticator.clearSession()
        }
    }

    @Test("A callback without a token fails without contacting Last.fm")
    func completeSignInWithoutToken() async throws {
        let requests = RequestRecorder()
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)",
            fetch: { url in
                await requests.record(url)
                return Data()
            }
        )
        let callbackURL = try #require(URL(string: "shfl://lastfm"))

        await #expect {
            try await authenticator.completeSignIn(callbackURL: callbackURL)
        } throws: { error in
            guard case LastFMAuthError.authenticationFailed(let message) = error else { return false }
            return message == "No token in callback"
        }
        #expect(await requests.urls.isEmpty)
        #expect(await authenticator.isAuthenticated == false)
    }

    @Test("An unreadable session response fails the exchange")
    func completeSignInWithBadResponse() async throws {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)",
            fetch: { _ in Data(#"{"error":4,"message":"Invalid authentication token"}"#.utf8) }
        )
        let callbackURL = try #require(URL(string: "shfl://lastfm?token=expired"))

        await #expect {
            try await authenticator.completeSignIn(callbackURL: callbackURL)
        } throws: { error in
            guard case LastFMAuthError.tokenExchangeFailed = error else { return false }
            return true
        }
        #expect(await authenticator.isAuthenticated == false)
    }

    @Test("Authentication failure preserves message")
    func authenticationFailureMessage() {
        let error = LastFMAuthError.authenticationFailed("Custom message")
        #expect(error.errorDescription == "Custom message")
    }
}

private actor RequestRecorder {
    private(set) var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }
}
