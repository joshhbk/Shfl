import SwiftUI

enum AppIconVariant: String, CaseIterable, Identifiable {
    case primary = "AppIcon"
    case blue = "AppIcon-blue"
    case purple = "AppIcon-purple"
    case orange = "AppIcon-orange"
    case gray = "AppIcon-green" // Bundle name preserved for compatibility

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .primary: "Default"
        case .blue: "Blue"
        case .purple: "Purple"
        case .orange: "Orange"
        case .gray: "Gray"
        }
    }

    var iconName: String? {
        self == .primary ? nil : rawValue
    }

    var previewImageName: String {
        rawValue
    }
}

struct AppIconSettingsView: View {
    @State private var currentIcon: AppIconVariant = .primary
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(AppIconVariant.allCases) { variant in
                    IconCell(
                        variant: variant,
                        isSelected: currentIcon == variant,
                        action: { setAppIcon(variant) }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("App Icon")
        .onAppear { loadCurrentIcon() }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadCurrentIcon() {
        if let iconName = UIApplication.shared.alternateIconName {
            currentIcon = AppIconVariant(rawValue: iconName) ?? .primary
        } else {
            currentIcon = .primary
        }
    }

    private func setAppIcon(_ variant: AppIconVariant) {
        guard currentIcon != variant else { return }

        UIApplication.shared.setAlternateIconName(variant.iconName) { error in
            Task { @MainActor in
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentIcon = variant
                    }
                }
            }
        }
    }
}

private struct IconCell: View {
    let variant: AppIconVariant
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(variant.previewImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(.rect(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                HStack(spacing: 6) {
                    Text(variant.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.background, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(variant.displayName) app icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        AppIconSettingsView()
    }
}
