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

    private static var volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: .zero)
        view.isHidden = true
        return view
    }()

    private static var volumeSlider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    private static func ensureVolumeViewInHierarchy() {
        guard volumeView.superview == nil,
              let window = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first?.windows.first else { return }
        window.addSubview(volumeView)
    }

    static func increaseVolume() {
        ensureVolumeViewInHierarchy()
        guard let slider = volumeSlider else {
            assertionFailure("VolumeController: Could not find volume slider in MPVolumeView hierarchy")
            return
        }
        let newValue = min(slider.value + volumeStep, 1.0)
        slider.value = newValue
        slider.sendActions(for: .touchUpInside)
    }

    static func decreaseVolume() {
        ensureVolumeViewInHierarchy()
        guard let slider = volumeSlider else {
            assertionFailure("VolumeController: Could not find volume slider in MPVolumeView hierarchy")
            return
        }
        let newValue = max(slider.value - volumeStep, 0.0)
        slider.value = newValue
        slider.sendActions(for: .touchUpInside)
    }
}
