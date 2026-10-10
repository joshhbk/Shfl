import Foundation
import SwiftData

/// One row holds the entire cross-launch session: the editable song pool and
/// the active listening session. Committing replaces the row atomically.
@Model
final class PersistedSession {
    var savedAt: Date
    var poolJSON: String
    var sessionJSON: String?

    init(savedAt: Date, poolJSON: String, sessionJSON: String?) {
        self.savedAt = savedAt
        self.poolJSON = poolJSON
        self.sessionJSON = sessionJSON
    }
}