import SwiftUI

/// Configuration for click wheel tactile feedback effects
struct ClickWheelFeedback {
    // MARK: - Wheel Tilt

    /// Rotation angle in degrees when a button is pressed (exaggerated = 10)
    static let tiltAngle: Double = 10

    /// Scale when wheel is pressed (0.98 = slight shrink to simulate sinking in)
    static let wheelPressScale: Double = 0.98

    /// Spring animation response time (higher = slower/heavier feel)
    static let springResponse: Double = 0.5

    /// Spring animation damping (0.7 = less bounce, more deliberate)
    static let springDampingFraction: Double = 0.7

    /// 3D perspective for rotation effect
    static let perspective: CGFloat = 0.3

    // MARK: - Center Button Depression

    /// Scale when pressed (0.92 = 8% smaller)
    static let centerPressScale: Double = 0.92

    /// Shadow radius when pressed
    static let centerPressedShadowRadius: CGFloat = 2

    /// Shadow Y offset when pressed
    static let centerPressedShadowY: CGFloat = 1

    /// Shadow radius when not pressed
    static let centerNormalShadowRadius: CGFloat = 8

    /// Shadow Y offset when not pressed
    static let centerNormalShadowY: CGFloat = 4
}

// MARK: - Press Position

/// Represents which button on the wheel is currently pressed
enum WheelPressPosition {
    case none
    case top      // Volume up
    case bottom   // Volume down
    case left     // Skip back
    case right    // Skip forward

    /// The 3D rotation axis for this press position
    var rotationAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        switch self {
        case .none:
            return (0, 0, 0)
        case .top:
            return (1, 0, 0)      // Tilt forward (top sinks in)
        case .bottom:
            return (-1, 0, 0)     // Tilt backward (bottom sinks in)
        case .left:
            return (0, -1, 0)     // Tilt left
        case .right:
            return (0, 1, 0)      // Tilt right
        }
    }
}
