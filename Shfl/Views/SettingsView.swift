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
                        Text("Shuffle algorithm settings coming soon")
                            .navigationTitle("Shuffle Algorithm")
                    } label: {
                        Label("Shuffle Algorithm", systemImage: "shuffle")
                    }

                    NavigationLink {
                        Text("Autofill settings coming soon")
                            .navigationTitle("Autofill")
                    } label: {
                        Label("Autofill", systemImage: "text.badge.plus")
                    }
                }

                Section("Connections") {
                    NavigationLink {
                        Text("Last.fm connection coming soon")
                            .navigationTitle("Last.fm")
                    } label: {
                        Label("Last.fm", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
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
