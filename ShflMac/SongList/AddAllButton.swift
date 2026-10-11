import ShflCore
import ShflDesign
import SwiftUI

/// Adds a whole artist or playlist to Picks, all or nothing. Waits until every song has loaded.
struct AddAllButton: View {
    let songs: [Song]
    let isLoaded: Bool
    let owner: String

    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let pickedIDs = drafting.songIDs
        let allPicked = !songs.isEmpty && songs.allSatisfy { pickedIDs.contains($0.id) }
        Button(allPicked ? "All Picked" : "Add All") { drafting.add(songs) }
            .buttonStyle(.primary)
            .disabled(!isLoaded || songs.isEmpty || allPicked)
            .help(allPicked ? "Every song in \(owner) is in your picks" : "Add every song in \(owner) to your picks")
            .accessibilityIdentifier("mac.collection.addAll")
    }
}

enum SongCount {
    static func text(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count.formatted()) songs"
    }

    static func subtitle(_ count: Int, isLoaded: Bool) -> String {
        isLoaded ? text(count) : "Loading songs…"
    }
}
