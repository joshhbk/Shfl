import Foundation

/// Callback container for player actions, enabling decoupled view composition
struct PlayerActions {
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onSkipBack: () -> Void
    let onManage: () -> Void
    let onAdd: () -> Void
    let onSettings: () -> Void
}
