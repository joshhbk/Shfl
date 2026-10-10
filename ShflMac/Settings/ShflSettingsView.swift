import SwiftUI

struct ShflSettingsView: View {
    var body: some View {
        TabView {
            Tab("Playback", systemImage: "shuffle") {
                PlaybackSettingsTab()
            }
            Tab("Library", systemImage: "music.note.list") {
                LibrarySettingsTab()
            }
            Tab("Last.fm", systemImage: "dot.radiowaves.left.and.right") {
                LastFMSettingsTab()
            }
        }
        .scenePadding()
        .frame(width: 480)
    }
}
