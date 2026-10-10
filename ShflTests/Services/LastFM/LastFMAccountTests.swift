import Foundation
import Testing
@testable import Shfl

@Suite("LastFMAccount Tests")
@MainActor
struct LastFMAccountTests {

    @Test("Backing out of sign-in returns to disconnected without an error")
    func cancelledSignInIsQuiet() async {
        let account = makeAccount()
        var offered: LastFMSignIn?

        await account.connect { signIn in
            offered = signIn
            return nil
        }

        #expect(offered?.callbackURLScheme == "shfl")
        #expect(account.connectionState == .disconnected)
        #expect(account.errorMessage == nil)
    }

    @Test("A redirect without a token shows the sign-in error")
    func callbackWithoutTokenShowsError() async {
        let account = makeAccount()

        await account.connect { _ in URL(string: "shfl://lastfm") }

        #expect(account.connectionState == .disconnected)
        #expect(account.errorMessage == "No token in callback")
    }

    private func makeAccount() -> LastFMAccount {
        let account = LastFMAccount()
        account.transport = LastFMTransport(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)",
            queueURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("lastfm-account-\(UUID().uuidString).json")
        )
        return account
    }
}
