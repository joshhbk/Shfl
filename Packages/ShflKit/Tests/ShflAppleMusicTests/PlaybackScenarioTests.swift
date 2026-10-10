import Foundation
import SwiftData
import Testing
@testable import ShflAppleMusic
@testable import ShflCore
@testable import ShflDeterministic

/// Playback scenarios that run unchanged against both transports: the
/// deterministic adapter, and the MusicKit adapter over a fake player that
/// reproduces MusicKit's quirks. A scenario failing for one transport only
/// means the two adapters disagree about behaviour the app relies on.
@MainActor
@Suite("Playback scenarios")
struct PlaybackScenarioTests {
    enum TransportKind: String, CaseIterable, CustomTestStringConvertible {
        case deterministic
        case musicKit

        var testDescription: String { rawValue }
    }

    private let songs = ["one", "two", "three"].map {
        Song(id: "i.\($0)", title: $0, artist: "Artist", albumTitle: "Album", artworkURL: nil)
    }

    @Test("A session plays in order, then a fresh one starts", arguments: TransportKind.allCases)
    func playsThroughThenStartsFreshSession(kind: TransportKind) async throws {
        let rig = try ScenarioRig(kind, songs: songs)
        try rig.draft.add(songs)
        try await rig.player.startFreshShuffle(seed: 11)
        let firstSession = try #require(rig.player.activeSession)

        for expected in firstSession.songOrder.dropFirst() {
            await rig.finishCurrentSong()
            try await eventually { rig.player.playbackState == .playing(expected) }
        }
        await rig.finishCurrentSong()

        try await eventually {
            rig.player.sessionEndCount == 1
                && rig.player.activeSession.map { $0.id != firstSession.id } == true
        }
        #expect(rig.player.playbackState.isPlaying)
        #expect(Set(rig.player.activeSession?.songIDs ?? []) == Set(songs.map(\.id)))
    }

    @Test("Skip forward, then back to the start", arguments: TransportKind.allCases)
    func skipsForwardAndBack(kind: TransportKind) async throws {
        let rig = try ScenarioRig(kind, songs: songs)
        try rig.draft.add(songs)
        try await rig.player.startFreshShuffle(seed: 11)
        let order = try #require(rig.player.activeSession?.songOrder)

        try await rig.player.skipToNext()
        try await eventually { rig.player.playbackState == .playing(order[1]) }

        try await rig.player.restartOrSkipToPrevious()
        try await eventually { rig.player.playbackState == .playing(order[0]) }
        #expect(rig.player.sessionEndCount == 0)
    }

    @Test("Pause and resume keep the session and song", arguments: TransportKind.allCases)
    func pausesAndResumes(kind: TransportKind) async throws {
        let rig = try ScenarioRig(kind, songs: songs)
        try rig.draft.add(songs)
        try await rig.player.startFreshShuffle(seed: 11)
        let session = try #require(rig.player.activeSession)
        let first = session.songOrder[0]

        await rig.player.pause()
        try await eventually { rig.player.playbackState == .paused(first) }

        try await rig.player.play()
        try await eventually { rig.player.playbackState == .playing(first) }
        #expect(rig.player.activeSession?.id == session.id)
    }

    @Test("Restore comes back paused at the saved song and position", arguments: TransportKind.allCases)
    func restoresPausedAtPosition(kind: TransportKind) async throws {
        let rig = try ScenarioRig(kind, songs: songs)
        try rig.draft.add(songs)
        let session = ListeningSession(songOrder: songs, algorithm: .noRepeat, seed: 3)

        let restored = await rig.player.restore(session, currentSongID: songs[1].id, playbackPosition: 42)

        #expect(restored)
        try await eventually { rig.player.playbackState == .paused(songs[1]) }
        #expect(rig.transport.currentPlaybackTime == 42)
        #expect(rig.transport.currentSongId == songs[1].id)
    }

    @Test("Seeking moves the playback position", arguments: TransportKind.allCases)
    func seeks(kind: TransportKind) async throws {
        let rig = try ScenarioRig(kind, songs: songs)
        try rig.draft.add(songs)
        try await rig.player.startFreshShuffle(seed: 11)

        rig.player.seek(to: 95)

        #expect(rig.transport.currentPlaybackTime == 95)
    }

    @Test("Removing every song leaves the current session playing", arguments: TransportKind.allCases)
    func removingEverythingKeepsPlaying(kind: TransportKind) async throws {
        let rig = try ScenarioRig(kind, songs: songs)
        try rig.draft.add(songs)
        try await rig.player.startFreshShuffle(seed: 11)
        let session = try #require(rig.player.activeSession)

        rig.draft.removeAll()
        await rig.finishCurrentSong()

        try await eventually { rig.player.playbackState == .playing(session.songOrder[1]) }
        #expect(rig.player.activeSession?.id == session.id)
    }

    @Test("When the session ends with an empty pool, playback stops", arguments: TransportKind.allCases)
    func emptyPoolStopsAtSessionEnd(kind: TransportKind) async throws {
        let rig = try ScenarioRig(kind, songs: songs)
        try rig.draft.add([songs[0]])
        try await rig.player.startFreshShuffle(seed: 11)

        rig.draft.removeAll()
        await rig.finishCurrentSong()

        try await eventually { rig.player.sessionEndCount == 1 }
        #expect(rig.player.activeSession == nil)
        #expect(rig.player.playbackState == .stopped)
    }

    @Test("Clearing the session stops playback", arguments: TransportKind.allCases)
    func clearingSessionStops(kind: TransportKind) async throws {
        let rig = try ScenarioRig(kind, songs: songs)
        try rig.draft.add(songs)
        try await rig.player.startFreshShuffle(seed: 11)

        await rig.player.clearSession()

        try await eventually { rig.player.playbackState == .empty }
        #expect(rig.player.activeSession == nil)
        #expect(rig.transport.currentSongId == nil)
        #expect(rig.draft.songCount == songs.count)
    }
}

/// One transport plus the session host and player that drive it, and a way to
/// let the current song play to its end.
@MainActor
private struct ScenarioRig {
    let transport: PlaybackTransport
    let host: ListeningSessionHost
    let finishCurrentSong: () async -> Void

    var draft: SessionDraftStore { host.sessionDraft }
    var player: ShufflePlayer { host.player }

    init(_ kind: PlaybackScenarioTests.TransportKind, songs: [Song]) throws {
        switch kind {
        case .deterministic:
            let service = DeterministicMusicService(
                configuration: .init(librarySongs: songs, playbackDuration: 180)
            )
            transport = service
            finishCurrentSong = {
                let remaining = service.currentSongDuration - service.currentPlaybackTime
                await service.advance(by: remaining)
            }
        case .musicKit:
            let fake = FakeMusicPlayer()
            transport = MusicKitTransport(player: fake, confirmationDelay: {})
            finishCurrentSong = { await fake.finishCurrentEntry() }
        }
        // Each rig gets its own storage.
        let container = try ModelContainer(
            for: PersistedSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        host = ListeningSessionHost(
            playbackTransport: transport,
            archive: SessionArchive(modelContext: container.mainContext),
            autofillSource: NoAutofillSource()
        )
        modelContainer = container
    }

    /// Keeps the in-memory store alive for as long as the host writes to it.
    private let modelContainer: ModelContainer
}

/// Scenarios start from a filled draft, so autofill never has songs to add.
@MainActor
private struct NoAutofillSource: WarmableAutofillSource {
    func warm() {}
    func fetchSongs(excluding: Set<String>, limit: Int) async throws -> [Song] { [] }
}

@MainActor
private func eventually(
    _ condition: @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    for _ in 0..<2_000 {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("Condition never became true", sourceLocation: sourceLocation)
    throw CancellationError()
}
