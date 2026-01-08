import Foundation
import Testing
@testable import Shfl

/// Check if running in CI environment (keychain not available)
private let isRunningOnCI: Bool = {
    ProcessInfo.processInfo.environment["CI"] != nil ||
    ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil
}()

/// Check if keychain is available (not on CI)
private let isKeychainAvailable: Bool = !isRunningOnCI

@Suite("LastFMAuthenticator Tests")
struct LastFMAuthenticatorTests {

    @Test("Store and retrieve session from keychain", .enabled(if: isKeychainAvailable, "Keychain not available in CI"))
    func storeAndRetrieve() async throws {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let session = LastFMSession(sessionKey: "abc123", username: "testuser")
        try await authenticator.storeSession(session)

        let retrieved = await authenticator.storedSession()
        #expect(retrieved?.sessionKey == "abc123")
        #expect(retrieved?.username == "testuser")

        // Cleanup
        try await authenticator.clearSession()
    }

    @Test("isAuthenticated returns true when session exists", .enabled(if: isKeychainAvailable, "Keychain not available in CI"))
    func isAuthenticatedTrue() async throws {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let session = LastFMSession(sessionKey: "abc123", username: "testuser")
        try await authenticator.storeSession(session)

        let isAuth = await authenticator.isAuthenticated
        #expect(isAuth == true)

        // Cleanup
        try await authenticator.clearSession()
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

    @Test("Clear session removes from keychain", .enabled(if: isKeychainAvailable, "Keychain not available in CI"))
    func clearSession() async throws {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let session = LastFMSession(sessionKey: "abc123", username: "testuser")
        try await authenticator.storeSession(session)
        try await authenticator.clearSession()

        let retrieved = await authenticator.storedSession()
        #expect(retrieved == nil)
    }
}
