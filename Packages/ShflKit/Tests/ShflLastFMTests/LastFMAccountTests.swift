import Foundation
import Testing
@testable import ShflLastFM

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

    @Test("A refresh after a failed connect clears the error")
    func refreshClearsAnEarlierConnectError() async {
        let account = makeAccount()
        await account.connect { _ in URL(string: "shfl://lastfm") }
        #expect(account.errorMessage != nil)

        await account.refreshActivity(showLoading: !account.recentTracksState.hasLoadedTracks)

        #expect(account.errorMessage == nil)
        #expect(account.connectionState == .disconnected)
    }

    @Test("Signing in shows the username and the recent tracks")
    func signingInLoadsRecentTracks() async {
        let track = LastFMRecentTrack(
            title: "Low Tide",
            artist: "Harbour Lights",
            artworkURL: nil,
            playedAt: nil,
            isNowPlaying: true
        )
        let account = LastFMAccount(connection: SignedInConnection(tracks: [track]))

        await account.connect { signIn in signIn.url }

        #expect(account.connectionState == .connected(username: "listener"))
        #expect(account.recentTracksState == .loaded([track]))
    }

    @Test("Without a connection the account stays signed out")
    func noConnectionStaysSignedOut() async {
        let account = LastFMAccount(connection: nil)
        var offered = false

        await account.syncConnectionStatusOnly()
        await account.connect { _ in
            offered = true
            return nil
        }

        #expect(!offered)
        #expect(account.connectionState == .disconnected)
        #expect(account.recentTracksState == .idle)
    }

    private func makeAccount() -> LastFMAccount {
        LastFMAccount(
            connection: LastFMTransport(
                apiKey: "testkey",
                sharedSecret: "testsecret",
                keychainService: "com.shfl.test.\(UUID().uuidString)",
                queueURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("lastfm-account-\(UUID().uuidString).json")
            )
        )
    }
}

/// Signs in as "listener" whatever the callback, and has `tracks` as their
/// recent scrobbles.
private actor SignedInConnection {
    private let tracks: [LastFMRecentTrack]
    private var session: LastFMSession?

    init(tracks: [LastFMRecentTrack]) {
        self.tracks = tracks
    }

    func storedSession() -> LastFMSession? { session }

    func fetchRecentTracks(limit: Int) -> [LastFMRecentTrack] {
        Array(tracks.prefix(limit))
    }

    nonisolated func signIn() -> LastFMSignIn {
        LastFMSignIn(url: URL(string: "https://www.last.fm/api/auth")!, callbackURLScheme: "shfl")
    }

    func completeSignIn(callbackURL: URL) -> LastFMSession {
        let session = LastFMSession(sessionKey: "key", username: "listener")
        self.session = session
        return session
    }

    func disconnect() {
        session = nil
    }
}

// Declared in an extension: Xcode 27 infers `nonisolated` onto an actor that
// lists a nonisolated protocol on its primary declaration, then rejects it.
extension SignedInConnection: LastFMConnection {}
