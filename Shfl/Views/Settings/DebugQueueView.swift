import SwiftUI
import UIKit

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

    @State private var lastSnapshotCopiedAt: Date?
    @State private var lastHardResetAt: Date?
    @State private var isPerformingHardReset = false
    @State private var showingHardResetConfirmation = false

    // Access observed properties directly to ensure SwiftUI tracks them
    private var queue: [Song] { player.lastShuffledQueue }
    private var usedAlgorithm: ShuffleAlgorithm { player.lastUsedAlgorithm }
    private var invariantCheck: QueueInvariantCheck { player.queueInvariantCheck }
    private var recentOperations: [QueueOperationRecord] { player.recentQueueOperations }

    var body: some View {
        List {
            queueOverviewSection
            transportParitySection
            invariantSection
            operationsSection
            diagnosticsExportSection
            hardResetSection
            shuffledQueueSection
        }
        .navigationTitle("Debug Queue")
        .alert("Hard Reset Queue?", isPresented: $showingHardResetConfirmation) {
            Button("Hard Reset", role: .destructive) {
                Task { await performHardReset() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the current queue, playback state, and operation journal so you can start from a clean baseline.")
        }
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
    private var transportParitySection: some View {
        Section {
            statusRow(
                title: "Transport Entries",
                value: "\(player.transportQueueEntryCount)",
                color: .secondary
            )
            statusRow(
                title: "Domain Queue",
                value: "\(queue.count)",
                color: .secondary
            )

            let transportParity = player.transportQueueEntryCount == queue.count
            statusRow(
                title: "Parity",
                value: transportParity ? "In Sync" : "Mismatch",
                color: transportParity ? .secondary : .red
            )
        } header: {
            Text("Transport Parity")
        } footer: {
            Text("Compares MusicKit transport queue entry count against domain queue size.")
        }
    }

    @ViewBuilder
    private var invariantSection: some View {
        Section {
            statusRow(
                title: "Status",
                value: invariantCheck.isHealthy ? "Healthy" : "Violation",
                color: invariantCheck.isHealthy ? .secondary : .red
            )
            statusRow(
                title: "Unique Queue IDs",
                value: invariantCheck.queueHasUniqueIDs ? "Yes" : "No",
                color: invariantCheck.queueHasUniqueIDs ? .secondary : .red
            )
            statusRow(
                title: "Pool/Queue Match",
                value: invariantCheck.poolAndQueueMembershipMatch ? "Yes" : "No",
                color: invariantCheck.poolAndQueueMembershipMatch ? .secondary : .red
            )
            statusRow(
                title: "Transport Count Match",
                value: invariantCheck.transportEntryCountMatchesQueue ? "Yes" : "No",
                color: invariantCheck.transportEntryCountMatchesQueue ? .secondary : .red
            )
            statusRow(
                title: "Transport Current Match",
                value: invariantCheck.transportCurrentMatchesDomain ? "Yes" : "No",
                color: invariantCheck.transportCurrentMatchesDomain ? .secondary : .red
            )
            statusRow(
                title: "Reasons",
                value: "\(invariantCheck.reasons.count)",
                color: invariantCheck.reasons.isEmpty ? .secondary : .red
            )

            ForEach(invariantCheck.reasons, id: \.self) { reason in
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Invariant Check")
        }
    }

    @ViewBuilder
    private var operationsSection: some View {
        Section {
            statusRow(
                title: "Stored",
                value: "\(recentOperations.count)",
                color: .secondary
            )

            ForEach(Array(recentOperations.prefix(12))) { operation in
                QueueOperationRow(operation: operation)
            }
        } header: {
            Text("Recent Operations")
        } footer: {
            Text("Operation journal is capped to the most recent \(QueueOperationJournal.maxRecords) entries.")
        }
    }

    @ViewBuilder
    private var diagnosticsExportSection: some View {
        Section {
            Button("Copy Diagnostics Snapshot") {
                let snapshot = player.exportQueueDiagnosticsSnapshot(trigger: "debug-queue-copy")
                UIPasteboard.general.string = snapshot
                lastSnapshotCopiedAt = Date()
            }

            if let copiedAt = lastSnapshotCopiedAt {
                Text("Copied at \(copiedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Snapshot Export")
        } footer: {
            Text("Includes queue IDs, invariants, and operation journal as JSON.")
        }
    }

    @ViewBuilder
    private var hardResetSection: some View {
        Section {
            Button(role: .destructive) {
                showingHardResetConfirmation = true
            } label: {
                if isPerformingHardReset {
                    HStack {
                        ProgressView()
                        Text("Resetting Queue...")
                    }
                } else {
                    Text("Hard Reset Queue")
                }
            }
            .disabled(isPerformingHardReset)

            if let resetAt = lastHardResetAt {
                Text("Last reset at \(resetAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Recovery")
        } footer: {
            Text("Use this when queue/transport state diverges and you want to restart from a known clean state.")
        }
    }

    @ViewBuilder
    private var shuffledQueueSection: some View {
        Section("Shuffled Queue Order") {
            if queue.isEmpty {
                Text("No queue yet. Add songs and press play.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(queue.enumerated()), id: \.offset) { index, song in
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

    @MainActor
    private func performHardReset() async {
        guard !isPerformingHardReset else { return }
        isPerformingHardReset = true
        await player.hardResetQueueForDebug()
        lastHardResetAt = Date()
        isPerformingHardReset = false
    }
}

private struct QueueOperationRow: View {
    let operation: QueueOperationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(operation.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(operation.invariantHealthy ? "Healthy" : "Violation")
                    .font(.caption2)
                    .foregroundStyle(operation.invariantHealthy ? Color.secondary : Color.red)
            }

            Text(operation.operation)
                .font(.caption)

            if let detail = operation.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
