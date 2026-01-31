import MediaPlayer
import UIKit

/// Controls system volume programmatically using MPVolumeView.
///
/// This utility accesses the internal UISlider within MPVolumeView to adjust volume.
/// Note: This relies on MPVolumeView's internal view hierarchy which is not part of
/// the public API and could change in future iOS versions.
///
/// The volume slider may be nil if:
/// - The MPVolumeView hasn't been added to the view hierarchy yet
/// - Apple changes the internal structure of MPVolumeView
/// - The view hierarchy lookup fails for other reasons
enum VolumeController {
    private static let volumeStep: Float = 0.0625 // 1/16, matches iOS default
    private static var isInitialized = false

    private static var volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: .zero)
        view.isHidden = true
        return view
    }()

    private static var volumeSlider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    /// Call this early in app lifecycle (e.g., from AppDelegate or initial view)
    /// to ensure the volume view is ready before user interaction.
    static func initialize() {
        guard !isInitialized else { return }
        isInitialized = true

        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else {
            assertionFailure("VolumeController: No window available during initialization")
            return
        }
        window.addSubview(volumeView)
        // Force layout so subviews are populated
        volumeView.layoutIfNeeded()
    }

    static func increaseVolume() {
        adjustVolume(by: volumeStep)
    }

    static func decreaseVolume() {
        adjustVolume(by: -volumeStep)
    }

    private static func adjustVolume(by delta: Float) {
        guard let slider = volumeSlider else {
            assertionFailure("VolumeController: Slider unavailable. Ensure initialize() is called on app launch.")
            return
        }
        let newValue = max(0.0, min(slider.value + delta, 1.0))
        slider.value = newValue
        slider.sendActions(for: .touchUpInside)
    }
}
