#if canImport(UIKit)
import UIKit
#endif

enum HapticFeedback {
    case light
    case medium
    case heavy
    case success
    case warning
    case error
    case milestone

    #if canImport(UIKit)
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let milestoneGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    func trigger() {
        switch self {
        case .light:
            Self.lightGenerator.impactOccurred()
        case .medium:
            Self.mediumGenerator.impactOccurred()
        case .heavy:
            Self.heavyGenerator.impactOccurred()
        case .success:
            Self.notificationGenerator.notificationOccurred(.success)
        case .warning:
            Self.notificationGenerator.notificationOccurred(.warning)
        case .error:
            Self.notificationGenerator.notificationOccurred(.error)
        case .milestone:
            // Three quick taps for celebration — dedicated generator to avoid
            // interference if .medium fires during the pulse window
            Self.milestoneGenerator.prepare()
            Self.milestoneGenerator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Self.milestoneGenerator.impactOccurred()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Self.milestoneGenerator.impactOccurred()
            }
        }
    }
    #else
    /// Macs have no haptic engine to match these patterns.
    func trigger() {}
    #endif
}
