import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    NavigationLink {
                        Text("App Icon settings coming soon")
                            .navigationTitle("App Icon")
                    } label: {
                        Label("App Icon", systemImage: "app.badge")
                    }
                }

                Section("Playback") {
                    NavigationLink {
                        ShuffleAlgorithmSettingsView()
                    } label: {
                        Label("Shuffle Algorithm", systemImage: "shuffle")
                    }

                    NavigationLink {
                        AutofillSettingsView()
                    } label: {
                        Label("Autofill", systemImage: "text.badge.plus")
                    }

                    NavigationLink {
                        LibrarySortingSettingsView()
                    } label: {
                        Label("Library Sorting", systemImage: "arrow.up.arrow.down")
                    }
                }

                Section("Connections") {
                    NavigationLink {
                        LastFMSettingsView()
                    } label: {
                        Label("Last.fm", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }

                #if DEBUG
                Section("Debug") {
                    NavigationLink {
                        DebugQueueView()
                    } label: {
                        Label("View Queue Order", systemImage: "list.number")
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
