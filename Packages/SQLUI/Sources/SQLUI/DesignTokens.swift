import SwiftUI

public enum SexiQLSpace {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 8
    public static let lg: CGFloat = 12
    public static let xl: CGFloat = 16
    public static let xxl: CGFloat = 20
    public static let xxxl: CGFloat = 24
}

public enum SexiQLRadius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 8
    public static let lg: CGFloat = 12
    public static let xl: CGFloat = 14
}

public enum SexiQLLayout {
    public static let sidebarMin: CGFloat = 180
    public static let sidebarIdeal: CGFloat = 240
    public static let sidebarMax: CGFloat = 360
    public static let inspectorMin: CGFloat = 220
    public static let inspectorIdeal: CGFloat = 280
    public static let inspectorMax: CGFloat = 380
    public static let editorMinHeight: CGFloat = 100
    public static let resultsMinHeight: CGFloat = 120
    public static let tabMaxWidth: CGFloat = 160
    public static let secondaryChromeHeight: CGFloat = 40
    public static let panelChromeHorizontal: CGFloat = 16
}

public enum SexiQLType {
    public static var sectionHeader: Font { .caption.weight(.semibold) }
    public static var rowTitle: Font { .callout }
    public static var rowSubtitle: Font { .caption }
    public static var meta: Font { .caption2 }
    public static var emptyTitle: Font { .title3.weight(.semibold) }
    public static var emptyBody: Font { .callout }
}
