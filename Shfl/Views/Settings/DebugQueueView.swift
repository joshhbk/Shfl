import SwiftUI

struct DebugQueueView: View {
    @Environment(\.shufflePlayer) private var player
    @Environment(\.appSettings) private var appSettings

    private var algorithm: ShuffleAlgorithm {
        appSettings?.shuffleAlgorithm ?? .noRepeat
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Current Setting")
                    Spacer()
                    Text(algorithm.displayName)
                        .foregroundStyle(.secondary)
                }

                if let player {
                    HStack {
                        Text("Algorithm Used")
                        Spacer()
                        Text(player.lastUsedAlgorithm.displayName)
                            .foregroundStyle(player.lastUsedAlgorithm == algorithm ? Color.secondary : Color.red)
                    }

                    HStack {
                        Text("Queue Size")
                        Spacer()
                        Text("\(player.lastShuffledQueue.count) songs")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if let player, player.lastUsedAlgorithm != algorithm {
                    Text("⚠️ Press play again to apply the new algorithm")
                }
            }

            Section("Shuffled Queue Order") {
                if let player {
                    if player.lastShuffledQueue.isEmpty {
                        Text("No queue yet. Add songs and press play.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(player.lastShuffledQueue.enumerated()), id: \.element.id) { index, song in
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
                } else {
                    Text("Player not available")
                        .foregroundStyle(.secondary)
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
