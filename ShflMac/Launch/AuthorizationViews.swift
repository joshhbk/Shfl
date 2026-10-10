import SwiftUI

struct AuthorizationNeededView: View {
    let requestAccess: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Apple Music Access", systemImage: "music.note")
        } description: {
            Text("Shuffled shuffles and plays songs from your Apple Music library.")
        } actions: {
            Button("Allow Apple Music Access") {
                Task { await requestAccess() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("mac.auth.allow")
        }
    }
}

struct AuthorizationDeniedView: View {
    @Environment(\.openURL) private var openURL

    private static let mediaPrivacySettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media"
    )

    var body: some View {
        ContentUnavailableView {
            Label("No Apple Music Access", systemImage: "hand.raised")
        } description: {
            Text("Allow Shuffled in System Settings under Privacy & Security, Media & Apple Music.")
        } actions: {
            if let url = Self.mediaPrivacySettings {
                Button("Open System Settings") { openURL(url) }
                    .accessibilityIdentifier("mac.auth.openSettings")
            }
        }
    }
}
