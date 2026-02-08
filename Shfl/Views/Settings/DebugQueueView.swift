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
    private var driftTelemetry: QueueDriftTelemetry { player.queueDriftTelemetry }

    private var reasonCounts: [(reason: QueueDriftReason, count: Int)] {
        driftTelemetry.detectionsByReason
            .map { ($0.key, $0.value) }
            .sorted { $0.reason.rawValue < $1.reason.rawValue }
    }

    private var triggerCounts: [(trigger: String, count: Int)] {
        driftTelemetry.detectionsByTrigger
            .map { ($0.key, $0.value) }
            .sorted { $0.trigger < $1.trigger }
    }

    var body: some View {
        List {
            queueOverviewSection
            driftTelemetrySection
            driftEventsSection
            shuffledQueueSection
        }
        .navigationTitle("Debug Queue")
    }

    @ViewBuilder
    private var queueOverviewSection: some View {
        Section {
            statusRow(
                title: "Current Setting",
                value: algorithm.displayName,
                color: .secondary
            )
            statusRow(
                title: "Algorithm Used",
                value: usedAlgorithm.displayName,
                color: usedAlgorithm == algorithm ? .secondary : .red
            )
            statusRow(
                title: "Song Pool",
                value: "\(player.songCount) songs",
                color: .secondary
            )
            statusRow(
                title: "Queue Order",
                value: "\(queue.count) songs",
                color: queue.count == player.songCount ? .secondary : .red
            )
        } footer: {
            queueOverviewFooter
        }
    }

    @ViewBuilder
    private var queueOverviewFooter: some View {
        if usedAlgorithm != algorithm {
            Text("⚠️ Press play again to apply the new algorithm")
        } else if queue.count != player.songCount && queue.count > 0 {
            Text("⚠️ Queue size doesn't match pool! Check console logs for details.")
        }
    }

    @ViewBuilder
    private var driftTelemetrySection: some View {
        Section {
            statusRow(
                title: "Detections",
                value: "\(driftTelemetry.detections)",
                color: driftTelemetry.detections == 0 ? .secondary : .primary
            )
            statusRow(
                title: "Reconciliations",
                value: "\(driftTelemetry.reconciliations)",
                color: .secondary
            )
            statusRow(
                title: "Unrepaired",
                value: "\(driftTelemetry.unrepairedDetections)",
                color: driftTelemetry.unrepairedDetections == 0 ? .secondary : .red
            )

            ForEach(reasonCounts, id: \.reason) { entry in
                statusRow(
                    title: entry.reason.displayName,
                    value: "\(entry.count)",
                    color: .secondary
                )
            }

            ForEach(triggerCounts, id: \.trigger) { entry in
                statusRow(
                    title: "Trigger: \(entry.trigger)",
                    value: "\(entry.count)",
                    color: .secondary,
                    titleFont: .caption
                )
            }
        } header: {
            Text("Drift Telemetry")
        } footer: {
            if driftTelemetry.detections == 0 {
                Text("No queue drift detected in this session.")
            }
        }
    }

    @ViewBuilder
    private var driftEventsSection: some View {
        if !driftTelemetry.recentEvents.isEmpty {
            Section("Recent Drift Events") {
                ForEach(Array(driftTelemetry.recentEvents.prefix(5))) { event in
                    DriftEventRow(event: event)
                }
            }
        }
    }

    @ViewBuilder
    private var shuffledQueueSection: some View {
        Section("Shuffled Queue Order") {
            if queue.isEmpty {
                Text("No queue yet. Add songs and press play.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(queue.enumerated()), id: \.element.id) { index, song in
                    ShuffledSongRow(
                        song: song,
                        position: index + 1,
                        showWeightedDetails: algorithm == .weightedByPlayCount || algorithm == .weightedByRecency
                    )
                }
            }
        }
    }

    private func statusRow(
        title: String,
        value: String,
        color: Color,
        titleFont: Font? = nil
    ) -> some View {
        HStack {
            Text(title)
                .font(titleFont)
            Spacer()
            Text(value)
                .foregroundStyle(color)
        }
    }
}

private struct DriftEventRow: View {
    let event: QueueDriftEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(event.repaired ? "Repaired" : "Unrepaired")
                    .font(.caption)
                    .foregroundStyle(event.repaired ? Color.secondary : Color.red)
            }

            Text("Trigger: \(event.trigger)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(reasonSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var reasonSummary: String {
        if event.reasons.isEmpty {
            return "Reasons: none"
        }
        let reasons = event.reasons.map(\.displayName).joined(separator: ", ")
        return "Reasons: \(reasons)"
    }
}

private struct ShuffledSongRow: View {
    let song: Song
    let position: Int
    let showWeightedDetails: Bool

    var body: some View {
        HStack(alignment: .top) {
            Text("\(position)")
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

                if showWeightedDetails {
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

#Preview {
    NavigationStack {
        DebugQueueView()
            .environment(\.shufflePlayer, ShufflePlayer(musicService: MockMusicService()))
            .environment(\.appSettings, AppSettings())
    }
}
