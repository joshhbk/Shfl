import CoreMotion
import SwiftUI

@Observable
final class MotionManager {
    private(set) var highlightOffset: CGPoint = .zero
    private(set) var isAvailable: Bool = false

    @ObservationIgnored private var pitch: Double = 0
    @ObservationIgnored private var roll: Double = 0
    @ObservationIgnored private var lastUpdateTime: CFTimeInterval = 0
    @ObservationIgnored private var sensitivity: CGFloat = 1.0
    @ObservationIgnored private var maxOffset: CGFloat = 220

    private let motionManager = CMMotionManager()
    private let sensorUpdateInterval: TimeInterval = 1.0 / 30.0  // 30Hz sensor reads
    private let uiUpdateInterval: TimeInterval = 1.0 / 20.0  // 20Hz UI updates (throttled)

    init() {
        isAvailable = motionManager.isDeviceMotionAvailable
    }

    deinit {
        stop()
    }

    func start(sensitivity: CGFloat = 1.0, maxOffset: CGFloat = 220) {
        guard motionManager.isDeviceMotionAvailable else { return }

        self.sensitivity = sensitivity
        self.maxOffset = maxOffset

        motionManager.deviceMotionUpdateInterval = sensorUpdateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.pitch = motion.attitude.pitch
            self.roll = motion.attitude.roll

            // Throttle UI updates to reduce view invalidations
            let now = CACurrentMediaTime()
            if now - self.lastUpdateTime >= self.uiUpdateInterval {
                self.lastUpdateTime = now
                self.highlightOffset = Self.highlightOffset(
                    pitch: self.pitch,
                    roll: self.roll,
                    sensitivity: self.sensitivity,
                    maxOffset: self.maxOffset
                )
            }
        }
    }

    func updateSettings(sensitivity: CGFloat, maxOffset: CGFloat) {
        self.sensitivity = sensitivity
        self.maxOffset = maxOffset
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

        // Map pitch/roll to offset
        // Roll: ±0.8 rad (~45°) for side-to-side tilt
        // Pitch: wider range since phone is typically held at an angle
        let clampedRoll = max(-0.8, min(0.8, roll))
        let clampedPitch = max(-1.2, min(1.2, pitch))

        let x = CGFloat(clampedRoll) * maxOffset * sensitivity / 0.8
        let y = CGFloat(clampedPitch) * maxOffset * sensitivity / 1.2

        return CGPoint(x: x, y: -y)  // Invert Y so tilting forward moves highlight up
    }
}
