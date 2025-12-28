import SwiftUI

struct LastFMSettingsView: View {
    @State private var isConnected = false
    @State private var username: String?
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private let transport = LastFMTransport(
        apiKey: LastFMConfig.apiKey,
        sharedSecret: LastFMConfig.sharedSecret
    )

    var body: some View {
        List {
            Section {
                if isConnected, let username = username {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connected")
                                    .font(.body)
                                Text(username)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Spacer()
                    }
                } else {
                    Label("Not connected", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if isConnected {
                    Button(role: .destructive) {
                        Task {
                            await disconnect()
                        }
                    } label: {
                        Label("Disconnect", systemImage: "link.badge.minus")
                    }
                } else {
                    Button {
                        Task {
                            await connect()
                        }
                    } label: {
                        HStack {
                            Label("Connect to Last.fm", systemImage: "link.badge.plus")
                            Spacer()
                            if isConnecting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isConnecting)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("When connected, Shfl will scrobble your plays to Last.fm. Songs must be played for at least half their duration (up to 4 minutes) to be scrobbled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Last.fm")
        .task {
            await checkConnectionStatus()
        }
    }

    private func checkConnectionStatus() async {
        if let session = await transport.storedSession() {
            isConnected = true
            username = session.username
        } else {
            isConnected = false
            username = nil
        }
    }

    @MainActor
    private func connect() async {
        isConnecting = true
        errorMessage = nil

        do {
            let session = try await transport.authenticate()
            isConnected = true
            username = session.username
        } catch LastFMAuthError.cancelled {
            // User cancelled, no error to show
        } catch {
            errorMessage = "Failed to connect. Please try again."
        }

        isConnecting = false
    }

    private func disconnect() async {
        do {
            try await transport.disconnect()
            isConnected = false
            username = nil
        } catch {
            errorMessage = "Failed to disconnect."
        }
    }
}

#Preview {
    NavigationStack {
        LastFMSettingsView()
    }
}
