import CoreGraphics

public enum Spacing {
    public static let s2: CGFloat = 2
    public static let s4: CGFloat = 4
    public static let s6: CGFloat = 6
    public static let s8: CGFloat = 8
    public static let s10: CGFloat = 10
    public static let s12: CGFloat = 12
    public static let s14: CGFloat = 14
    public static let s16: CGFloat = 16
    public static let s20: CGFloat = 20
    public static let s24: CGFloat = 24
    public static let s32: CGFloat = 32
}

public enum CornerRadius {
    /// Tray tiles and artwork up to 26pt.
    public static let tile: CGFloat = 4
    /// Tags and 34pt row artwork.
    public static let tag: CGFloat = 5
    /// 28pt controls: quiet buttons, search fields, sidebar items, menu rows.
    public static let control: CGFloat = 7
    /// 30–32pt controls, segmented tracks, row highlights, 56–68pt artwork.
    public static let regular: CGFloat = 8
    /// 38pt buttons, menus and settings groups.
    public static let panel: CGFloat = 10
    /// Large artwork, cards and notices.
    public static let card: CGFloat = 12
    /// Pill toolbars and popovers.
    public static let popover: CGFloat = 16
    public static let miniPlayer: CGFloat = 26
}

public enum ArtworkSize {
    public static let hero: CGFloat = 232
    public static let miniPlayer: CGFloat = 208
    public static let compact: CGFloat = 68
    public static let menuBar: CGFloat = 56
    public static let row: CGFloat = 34
    public static let listRow: CGFloat = 26
}
