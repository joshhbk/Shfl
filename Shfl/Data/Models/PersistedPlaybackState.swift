import Foundation
import SwiftData

@Model
final class PersistedPlaybackState {
    var currentSongId: String?
    var playbackPosition: Double
    var savedAt: Date
    var queueOrderJSON: String
    var playedSongIdsJSON: String

    init(
        currentSongId: String?,
        playbackPosition: Double,
        savedAt: Date,
        queueOrderJSON: String,
        playedSongIdsJSON: String
    ) {
        self.currentSongId = currentSongId
        self.playbackPosition = playbackPosition
        self.savedAt = savedAt
        self.queueOrderJSON = queueOrderJSON
        self.playedSongIdsJSON = playedSongIdsJSON
    }
}

// MARK: - JSON Encoding/Decoding Helpers

extension PersistedPlaybackState {
    var queueOrder: [String] {
        get {
            guard !queueOrderJSON.isEmpty else { return [] }
            guard let data = queueOrderJSON.data(using: .utf8),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return ids
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                queueOrderJSON = "[]"
                return
            }
            queueOrderJSON = json
        }
    }

    var playedSongIds: Set<String> {
        get {
            guard !playedSongIdsJSON.isEmpty else { return [] }
            guard let data = playedSongIdsJSON.data(using: .utf8),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return Set(ids)
        }
        set {
            let array = Array(newValue)
            guard let data = try? JSONEncoder().encode(array),
                  let json = String(data: data, encoding: .utf8) else {
                playedSongIdsJSON = "[]"
                return
            }
            playedSongIdsJSON = json
        }
    }
}

// MARK: - Convenience Initializer

extension PersistedPlaybackState {
    convenience init(
        currentSongId: String?,
        playbackPosition: Double,
        queueOrder: [String],
        playedSongIds: Set<String>
    ) {
        let queueJSON: String
        if let data = try? JSONEncoder().encode(queueOrder),
           let json = String(data: data, encoding: .utf8) {
            queueJSON = json
        } else {
            queueJSON = "[]"
        }

        let playedJSON: String
        if let data = try? JSONEncoder().encode(Array(playedSongIds)),
           let json = String(data: data, encoding: .utf8) {
            playedJSON = json
        } else {
            playedJSON = "[]"
        }

        self.init(
            currentSongId: currentSongId,
            playbackPosition: playbackPosition,
            savedAt: Date(),
            queueOrderJSON: queueJSON,
            playedSongIdsJSON: playedJSON
        )
    }
}
