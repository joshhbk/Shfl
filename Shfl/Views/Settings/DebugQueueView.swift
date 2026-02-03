import SwiftUI

struct DebugQueueView: View {
    @Environment(\.shufflePlayer) private var player
    @Environment(\.appSettings) private var appSettings

    private var algorithm: ShuffleAlgorithm {
        appSettings?.shuffleAlgorithm ?? .noRepeat
    }

    var body: some View {
        if let player {
            DebugQueueContent(player: player, algorithm: algorithm)
        } else {
            Text("Player not available")
        }
    }
}

/// Extracted to ensure proper observation of @Observable player
private struct DebugQueueContent: View {
    let player: ShufflePlayer
    let algorithm: ShuffleAlgorithm

    // Access observed properties directly to ensure SwiftUI tracks them
    private var queue: [Song] { player.lastShuffledQueue }
    private var usedAlgorithm: ShuffleAlgorithm { player.lastUsedAlgorithm }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Current Setting")
                    Spacer()
                    Text(algorithm.displayName)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Algorithm Used")
                    Spacer()
                    Text(usedAlgorithm.displayName)
                        .foregroundStyle(usedAlgorithm == algorithm ? Color.secondary : Color.red)
                }

                HStack {
                    Text("Song Pool")
                    Spacer()
                    Text("\(player.songCount) songs")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Queue Order")
                    Spacer()
                    Text("\(queue.count) songs")
                        .foregroundStyle(queue.count == player.songCount ? Color.secondary : Color.red)
                }
            } footer: {
                if usedAlgorithm != algorithm {
                    Text("⚠️ Press play again to apply the new algorithm")
                } else if queue.count != player.songCount && queue.count > 0 {
                    Text("⚠️ Queue size doesn't match pool! Check console logs for details.")
                }
            }

            Section("Shuffled Queue Order") {
                if queue.isEmpty {
                    Text("No queue yet. Add songs and press play.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(queue.enumerated()), id: \.element.id) { index, song in
                        HStack(alignment: .top) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)

                            VStack(alignment: .leading) {
                                Text(song.title)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                if algorithm == .weightedByPlayCount || algorithm == .weightedByRecency {
                                    HStack(spacing: 8) {
                                        Text("Plays: \(song.playCount)")
                                        if let date = song.lastPlayedDate {
                                            Text("Last: \(date, style: .relative)")
                                        } else {
                                            Text("Never played")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Debug Queue")
    }
}

#Preview {
    NavigationStack {
        DebugQueueView()
            .environment(\.shufflePlayer, ShufflePlayer(musicService: MockMusicService()))
            .environment(\.appSettings, AppSettings())
    }
}
