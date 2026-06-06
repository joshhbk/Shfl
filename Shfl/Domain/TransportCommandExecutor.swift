import Foundation

/// Error thrown when a transport command's revision doesn't match the current queue revision.
enum TransportCommandExecutionError: Error {
    case staleRevision(commandRevision: Int, queueRevision: Int)
}

/// Serializes transport command batches without building an unbounded linked task chain.
///
/// Commands are enqueued as batches. Each batch is drained sequentially: commands within
/// a batch run in order, and batches run in FIFO order. Only one batch drains at a time.
@MainActor
final class TransportCommandExecutor {
    typealias CommandRunner = (TransportCommand) async throws -> Void

    private struct Batch {
        let commands: [TransportCommand]
        let continuation: CheckedContinuation<Void, Error>
    }

    private let runCommand: CommandRunner
    private var pendingBatches: [Batch] = []
    private var isDraining = false

    init(runCommand: @escaping CommandRunner) {
        self.runCommand = runCommand
    }

    func enqueue(_ commands: [TransportCommand]) async throws {
        guard !commands.isEmpty else { return }

        try await withCheckedThrowingContinuation { continuation in
            pendingBatches.append(Batch(commands: commands, continuation: continuation))
            guard !isDraining else { return }
            isDraining = true
            Task { @MainActor [weak self] in
                await self?.drain()
            }
        }
    }

    private func drain() async {
        while !pendingBatches.isEmpty {
            let batch = pendingBatches.removeFirst()
            do {
                for command in batch.commands {
                    try await runCommand(command)
                }
                batch.continuation.resume(returning: ())
            } catch {
                batch.continuation.resume(throwing: error)
            }
        }

        isDraining = false
    }
}