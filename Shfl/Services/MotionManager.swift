import CoreMotion
import SwiftUI

@Observable
final class MotionManager {
    private(set) var pitch: Double = 0
    private(set) var roll: Double = 0
    private(set) var isAvailable: Bool = false

    private let motionManager = CMMotionManager()
    private let updateInterval: TimeInterval = 1.0 / 30.0  // 30Hz

    init() {
        isAvailable = motionManager.isDeviceMotionAvailable
    }

    deinit {
        stop()
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion = motion else { return }
            self?.pitch = motion.attitude.pitch
            self?.roll = motion.attitude.roll
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - Calculations (static for testability)

    static func highlightOffset(
        pitch: Double,
        roll: Double,
        sensitivity: CGFloat,
        maxOffset: CGFloat
    ) -> CGPoint {
        guard sensitivity > 0 else { return .zero }

        // Map pitch/roll (-π to π) to offset (-maxOffset to maxOffset)
        // Clamp to reasonable range (about ±45 degrees of tilt)
        let clampedPitch = max(-0.8, min(0.8, pitch))
        let clampedRoll = max(-0.8, min(0.8, roll))

        let x = CGFloat(clampedRoll) * maxOffset * sensitivity / 0.8
        let y = CGFloat(clampedPitch) * maxOffset * sensitivity / 0.8

        return CGPoint(x: x, y: -y)  // Invert Y so tilting forward moves highlight up
    }
}
