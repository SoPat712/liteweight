import SwiftUI
import UIKit
import WorkoutDataKit

// MARK: - Cupertino visual system

/// One explicit palette record. Screens consume the semantic aliases in
/// `LiteweightTheme`; palette values only live here so light, dark, and modal
/// surfaces cannot drift into one-off system colors.
struct LiteweightPaletteColors {
    let accent: UIColor
    let accentPressed: UIColor
    let accentContainer: UIColor
    let metricSets: UIColor
    let metricSetsContainer: UIColor
    let metricVolume: UIColor
    let metricVolumeContainer: UIColor
    let metricTime: UIColor
    let metricTimeContainer: UIColor
    let metricEffort: UIColor
    let metricEffortContainer: UIColor
    let metricRecord: UIColor
    let metricRecordContainer: UIColor
    let metricBody: UIColor
    let metricBodyContainer: UIColor
    let metricHeartRate: UIColor
    let metricEnergy: UIColor
    let success: UIColor
    let successContainer: UIColor
    let successControl: UIColor
    let onSuccessContainer: UIColor
    let warning: UIColor
    let danger: UIColor
    let canvas: UIColor
    let modalSurface: UIColor
    let surface: UIColor
    let raisedSurface: UIColor
    let field: UIColor
    let topBar: UIColor
    let outline: UIColor
    let primaryText: UIColor
    let secondaryText: UIColor
    let tertiaryText: UIColor
    let onAccent: UIColor
}

/// liteweight uses Apple's adaptive semantic colors instead of maintaining separate
/// hard-coded light and dark palettes. Keeping the roles centralized prevents
/// local screens from guessing at contrast or appearance-specific values.
enum LiteweightPalette {
    static let semantic = LiteweightPaletteColors(
        accent: .systemBlue,
        accentPressed: UIColor.systemBlue.withAlphaComponent(0.72),
        accentContainer: UIColor.systemBlue.withAlphaComponent(0.12),
        metricSets: .systemOrange,
        metricSetsContainer: UIColor.systemOrange.withAlphaComponent(0.18),
        metricVolume: .systemGreen,
        metricVolumeContainer: UIColor.systemGreen.withAlphaComponent(0.18),
        metricTime: .systemCyan,
        metricTimeContainer: UIColor.systemCyan.withAlphaComponent(0.18),
        metricEffort: .systemPink,
        metricEffortContainer: UIColor.systemPink.withAlphaComponent(0.18),
        metricRecord: .systemYellow,
        metricRecordContainer: UIColor.systemYellow.withAlphaComponent(0.18),
        metricBody: .systemPurple,
        metricBodyContainer: UIColor.systemPurple.withAlphaComponent(0.18),
        metricHeartRate: .systemRed,
        metricEnergy: .systemOrange,
        success: .systemGreen,
        successContainer: UIColor.systemGreen.withAlphaComponent(0.14),
        successControl: UIColor.systemGreen.withAlphaComponent(0.22),
        // Legacy success containers remain source-compatible during the refresh.
        // New completed-set treatments use accent, never success.
        onSuccessContainer: .label,
        warning: .systemOrange,
        danger: .systemRed,
        canvas: .systemGroupedBackground,
        modalSurface: .systemGroupedBackground,
        surface: .secondarySystemGroupedBackground,
        raisedSurface: .tertiarySystemGroupedBackground,
        field: .secondarySystemFill,
        topBar: .systemBackground,
        outline: .separator,
        primaryText: .label,
        secondaryText: .secondaryLabel,
        tertiaryText: .tertiaryLabel,
        onAccent: .white
    )

    static func uiColor(_ role: KeyPath<LiteweightPaletteColors, UIColor>) -> UIColor {
        semantic[keyPath: role]
    }

    static func color(_ role: KeyPath<LiteweightPaletteColors, UIColor>) -> Color {
        Color(uiColor(role))
    }
}

/// liteweight follows Apple's platform conventions: semantic colors, SF typography,
/// grouped content surfaces, standard control geometry, and restrained tint.
enum LiteweightTheme {
    static let accent = LiteweightPalette.color(\.accent)
    static let accentPressed = LiteweightPalette.color(\.accentPressed)
    static let accentSoft = LiteweightPalette.color(\.accentContainer)
    static let metricSets = LiteweightPalette.color(\.metricSets)
    static let metricSetsContainer = LiteweightPalette.color(\.metricSetsContainer)
    static let metricVolume = LiteweightPalette.color(\.metricVolume)
    static let metricVolumeContainer = LiteweightPalette.color(\.metricVolumeContainer)
    static let metricTime = LiteweightPalette.color(\.metricTime)
    static let metricTimeContainer = LiteweightPalette.color(\.metricTimeContainer)
    static let metricEffort = LiteweightPalette.color(\.metricEffort)
    static let metricEffortContainer = LiteweightPalette.color(\.metricEffortContainer)
    static let metricRecord = LiteweightPalette.color(\.metricRecord)
    static let metricRecordContainer = LiteweightPalette.color(\.metricRecordContainer)
    static let metricBody = LiteweightPalette.color(\.metricBody)
    static let metricBodyContainer = LiteweightPalette.color(\.metricBodyContainer)
    static let metricHeartRate = LiteweightPalette.color(\.metricHeartRate)
    static let metricEnergy = LiteweightPalette.color(\.metricEnergy)
    static let setWarmUpTint = Color(UIColor.systemOrange)
    static let setDropTint = Color(UIColor.systemIndigo)
    static let setFailureTint = Color(UIColor.systemRed)
    static let setWarmUpContainer = setWarmUpTint.opacity(0.18)
    static let setDropContainer = setDropTint.opacity(0.18)
    static let setFailureContainer = setFailureTint.opacity(0.16)

    static func setFill(for tag: WorkoutSetTag?) -> (tint: Color, settled: Double, peak: Double) {
        switch tag {
        case .warmUp: return (setWarmUpTint, 0.14, 0.22)
        case .dropSet: return (setDropTint, 0.14, 0.22)
        case .failure: return (setFailureTint, 0.12, 0.20)
        case nil: return (accent, 0.12, 0.24)
        }
    }

    static let success = LiteweightPalette.color(\.success)
    static let successContainer = LiteweightPalette.color(\.successContainer)
    static let successControl = LiteweightPalette.color(\.successControl)
    static let onSuccessContainer = LiteweightPalette.color(\.onSuccessContainer)
    static let warning = LiteweightPalette.color(\.warning)
    static let danger = LiteweightPalette.color(\.danger)
    static let background = LiteweightPalette.color(\.canvas)
    static let modalSurface = LiteweightPalette.color(\.modalSurface)
    static let surface = LiteweightPalette.color(\.surface)
    static let raisedSurface = LiteweightPalette.color(\.raisedSurface)
    static let field = LiteweightPalette.color(\.field)
    /// Quiet input fills and the rest ring's neutral track.
    static let tertiaryFill = Color(UIColor.tertiarySystemFill)
    /// An unfilled graph bar that stays solid whatever sits behind it.
    static let solidTrack = Color(UIColor.systemGray4)
    static let topBar = LiteweightPalette.color(\.topBar)
    static let outline = LiteweightPalette.color(\.outline)
    static let primaryText = LiteweightPalette.color(\.primaryText)
    static let secondaryText = LiteweightPalette.color(\.secondaryText)
    static let tertiaryText = LiteweightPalette.color(\.tertiaryText)
    static let onAccent = LiteweightPalette.color(\.onAccent)

    // Exercise diagrams and user media intentionally keep a fixed canvas so
    // third-party artwork and photo controls retain predictable contrast in
    // both appearances. Keep those fixed colors semantic and centralized.
    static let diagramCanvas = Color(UIColor.white)
    static let mediaBackdrop = Color(UIColor.black)
    static let onMedia = Color(UIColor.white)
    static let mediaControlSurface = Color(UIColor.white.withAlphaComponent(0.16))
    static let mediaBadgeSurface = Color(UIColor.black.withAlphaComponent(0.56))

    static let cornerRadius: CGFloat = 12
    static let compactCornerRadius: CGFloat = 10
    /// Hero and summary glass clusters use a larger continuous corner so they
    /// read as an Apple Fitness surface rather than a content card.
    static let heroCornerRadius: CGFloat = 22
    static let controlHeight: CGFloat = 44
    static let iconButtonSize: CGFloat = controlHeight
    static let pillCornerRadius: CGFloat = controlHeight / 2
    static let horizontalPadding: CGFloat = 16
    /// The native five-item tab bar occupies almost the full phone width. The
    /// active workout pill is intentionally four points narrower on each side
    /// and sits close enough to read as a companion surface.
    static let activeWorkoutPillHorizontalPadding: CGFloat = 20
    static let activeWorkoutPillBottomOffset: CGFloat = 66
    /// Bottom breathing room for destination content while the global active-
    /// workout glass pill floats above the tab bar. Full-screen editors also
    /// use this value because the pill intentionally remains available there.
    static let floatingWorkoutBottomClearance: CGFloat = 152
}


/// Motion uses springs for state changes and a decelerating curve for travel.
/// Every spatial animation remains defeasible by Reduce Motion.
enum LiteweightMotion {
    /// Direct manipulation and state changes the finger caused: set complete,
    /// header collapse, filter selection.
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// Layout changes that move a large surface, such as the logger summary
    /// collapsing into the floating pill.
    static let collapse = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Guided travel between exercises: move promptly, then settle without bounce.
    static let focusScroll = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.65)
    /// Non-spatial changes where a spring would look decorative.
    static let fade = Animation.easeInOut(duration: 0.18)

    /// Reduce Motion swaps springs for a short cross-fade rather than removing
    /// feedback entirely, so state changes are still perceivable.
    static func preferred(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }
}

