import SwiftUI

struct DebugQueueView: View {
    @EnvironmentObject private var player: ShufflePlayer
    @AppStorage("shuffleAlgorithm") private var algorithmRaw: String = ShuffleAlgorithm.noRepeat.rawValue

    private var algorithm: ShuffleAlgorithm {
        ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Algorithm")
                    Spacer()
                    Text(algorithm.displayName)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Queue Size")
                    Spacer()
                    Text("\(player.lastShuffledQueue.count) songs")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Shuffled Queue Order") {
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
            }
        }
        .navigationTitle("Debug Queue")
    }
}

#Preview {
    NavigationStack {
        DebugQueueView()
            .environmentObject(ShufflePlayer(musicService: MockMusicService()))
    }
}
