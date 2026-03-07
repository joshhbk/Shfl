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
    static func queueOrderJSONString(from queueOrder: [String]) -> String {
        guard let data = try? JSONEncoder().encode(queueOrder),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    static func playedSongIdsJSONString(from playedSongIds: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(Array(playedSongIds)),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

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
        self.init(
            currentSongId: currentSongId,
            playbackPosition: playbackPosition,
            savedAt: Date(),
            queueOrderJSON: Self.queueOrderJSONString(from: queueOrder),
            playedSongIdsJSON: Self.playedSongIdsJSONString(from: playedSongIds)
        )
    }
}

extension PlaybackSessionSnapshot {
    init(model: PersistedPlaybackState) {
        self.currentSongId = model.currentSongId
        self.playbackPosition = model.playbackPosition
        self.savedAt = model.savedAt
        self.queueOrder = model.queueOrder
        self.playedSongIds = model.playedSongIds
    }
}
