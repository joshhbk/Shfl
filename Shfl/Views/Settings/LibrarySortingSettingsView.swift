import SwiftUI

extension Notification.Name {
    static let librarySortingChanged = Notification.Name("librarySortingChanged")
}

struct LibrarySortingSettingsView: View {
    @AppStorage("librarySortOption") private var sortOptionRaw: String = SortOption.mostPlayed.rawValue

    private var sortOption: SortOption {
        SortOption(rawValue: sortOptionRaw) ?? .mostPlayed
    }

    var body: some View {
        Form {
            Section {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        guard sortOptionRaw != option.rawValue else { return }
                        sortOptionRaw = option.rawValue
                        NotificationCenter.default.post(name: .librarySortingChanged, object: nil)
                    } label: {
                        HStack {
                            Text(option.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if sortOption == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Library Sorting")
    }
}

#Preview {
    NavigationStack {
        LibrarySortingSettingsView()
    }
}
