import Foundation
import Testing
@testable import Shfl

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
}
