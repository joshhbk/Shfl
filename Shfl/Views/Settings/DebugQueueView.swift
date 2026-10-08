import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct DebugQueueView: View {
    @Environment(\.shufflePlayer) private var player

    var body: some View {
        if let player {
            DebugListeningSessionContent(player: player)
        } else {
            Text("Player not available")
        }
    }
}

private struct DebugListeningSessionContent: View {
    let player: ShufflePlayer

    @Environment(\.sessionDraft) private var sessionDraft
    @State private var showingResetConfirmation = false
    @State private var copiedAt: Date?

    var body: some View {
        List {
            Section("Draft") {
                row("Songs", "\(sessionDraft.songCount)")
                row("Algorithm", sessionDraft.algorithm.displayName)
                row("Pending changes", player.hasPendingSessionChanges ? "Yes" : "No")
            }

            Section("Active Listening Session") {
                if let session = player.activeSession {
                    row("ID", session.id.uuidString)
                    row("Seed", String(session.seed))
                    row("Algorithm", session.algorithm.displayName)
                    row("Songs", "\(session.songOrder.count)")
                    row("Current transport ID", player.transportCurrentSongId ?? "None")
                } else {
                    Text("No active session")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recent Events") {
                if player.recentPlaybackTrace.isEmpty {
                    Text("No events")
                        .foregroundStyle(.secondary)
                }
                ForEach(player.recentPlaybackTrace.prefix(20)) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.event)
                            Spacer()
                            Text(entry.timestamp, style: .time)
                                .foregroundStyle(.secondary)
                        }
                        if let detail = entry.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Exact Session Order") {
                if let session = player.activeSession {
                    ForEach(Array(session.songOrder.enumerated()), id: \.element.id) { index, song in
                        VStack(alignment: .leading) {
                            Text("\(index + 1). \(song.title)")
                            Text("\(song.artist) · \(song.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Start a shuffle to create a session.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Copy Session Diagnostics") {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = diagnostics
                    #else
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnostics, forType: .string)
                    #endif
                    copiedAt = Date()
                }
                if let copiedAt {
                    Text("Copied at \(copiedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Clear Draft and Session", role: .destructive) {
                    showingResetConfirmation = true
                }
            } footer: {
                Text("Clear is intentionally destructive. Ordinary edits never change active playback.")
            }
        }
        .navigationTitle("Playback Diagnostics")
        .alert("Clear everything?", isPresented: $showingResetConfirmation) {
            Button("Clear", role: .destructive) {
                sessionDraft.removeAll()
                Task { await player.hardResetQueueForDebug() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var diagnostics: String {
        let session = player.activeSession
        let trace = player.recentPlaybackTrace.map {
            "\($0.timestamp.ISO8601Format()) \($0.event) \($0.detail ?? "")"
        }.joined(separator: "\n")
        return """
        draft.count=\(sessionDraft.songCount)
        draft.algorithm=\(sessionDraft.algorithm.rawValue)
        pending=\(player.hasPendingSessionChanges)
        session.id=\(session?.id.uuidString ?? "none")
        session.seed=\(session.map { String($0.seed) } ?? "none")
        session.algorithm=\(session?.algorithm.rawValue ?? "none")
        session.order=\(session?.songIDs.joined(separator: ",") ?? "")
        transport.current=\(player.transportCurrentSongId ?? "none")

        \(trace)
        """
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

#Preview {
    NavigationStack {
        DebugQueueView()
            .environment(
                \.shufflePlayer,
                ShufflePlayer(playbackTransport: DeterministicMusicService(), sessionDraft: SessionDraftStore())
            )
    }
}
