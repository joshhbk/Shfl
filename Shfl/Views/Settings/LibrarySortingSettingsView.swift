import SwiftUI

struct LibrarySortingSettingsView: View {
    @Environment(\.appSettings) private var appSettings

    var body: some View {
        Form {
            Section {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        appSettings?.librarySortOption = option
                    } label: {
                        HStack {
                            Text(option.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if appSettings?.librarySortOption == option {
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
    .environment(\.appSettings, AppSettings())
}
