import AppKit
import CodexBarCore
import MacDesignSystem
import SwiftUI

/// Fluid Functionalism metrics for the usage board, on MacDesignSystem colors and radii.
///
/// The board is one compact region: control height 28, row padding 6, gap 4.
/// Comfortable values (36 / 8 / 8) stay here so the step-down is visible.
/// Sizes scale with the system body size (`UsageBoardScaledFont`) so Dynamic Type
/// still applies. SF Pro stands in for Inter. The accent is selection and focus only.
enum UsageBoardMetrics {
    static let controlComfortable: CGFloat = 36
    static let control: CGFloat = 28
    static let padComfortable: CGFloat = 8
    static let pad: CGFloat = 6
    static let gapComfortable: CGFloat = 8
    static let gap: CGFloat = 4
    static let iconComfortable: CGFloat = 16
    /// Compact Fluid Functionalism is 14. Sixteen keeps the SF Symbol on the HIG grid.
    static let icon: CGFloat = 16
    static let radiusWindow: CGFloat = 12
    /// Cards inset from the window share the design system's row radius (8).
    static let radiusCard: CGFloat = MacRadius.row
    /// Small items (rows, buttons, banners) use the design system's tile radius (6).
    static let radiusItem: CGFloat = MacRadius.iconTile
    static let hairline: CGFloat = MacSize.border
    static let focusRing: CGFloat = 2
    static let progress: CGFloat = 3
    static let windowPad: CGFloat = 8

    enum Role {
        case title
        case subtitle
        case body
        case caption
        case micro
        case percent
    }

    /// Compact step. Comfortable sizes are title 16/22, subtitle 14/20, body 13/20,
    /// caption 12/16, micro 11/14.
    static func size(_ role: Role) -> CGFloat {
        switch role {
        case .title, .percent: 15
        case .subtitle: 13
        case .body: 12
        case .caption: 11
        case .micro: 11
        }
    }

    static func weight(_ role: Role) -> Font.Weight {
        switch role {
        case .title, .percent: .semibold
        case .subtitle, .body, .caption, .micro: .regular
        }
    }

    static func usesDigits(_ role: Role) -> Bool {
        switch role {
        case .percent, .caption: true
        case .title, .subtitle, .body, .micro: false
        }
    }

    /// Inner radius for a surface inset by `pad` inside a parent of `outer` radius.
    static func nestedRadius(outer: CGFloat, pad: CGFloat, border: CGFloat = hairline) -> CGFloat {
        max(0, outer - pad - border)
    }
}

enum UsageBoardMotion {
    static let fast: Double = 0.08
    static let fastExit: Double = 0.06
    static let moderate: Double = 0.16
    static let slow: Double = 0.24

    static var fastSpring: Animation {
        .spring(response: fast, dampingFraction: 1)
    }

    static var moderateSpring: Animation {
        .spring(response: moderate, dampingFraction: 1)
    }

    static var fastExitTween: Animation {
        .easeOut(duration: fastExit)
    }
}

/// Colors come from MacDesignSystem's semantic tokens, so the board follows the app's light or dark
/// appearance like the rest of Tolkein's Mac UI. Dark keeps the near-black floor with one step of
/// elevation; light uses the design system's white panels on a near-white window.
enum UsageBoardTheme {
    static let canvas = MacColor.window
    static let surface = MacColor.panel
    static let card = MacColor.panel
    static let cardRaised = MacColor.raised
    static let hairline = MacColor.hairline
    static let track = MacColor.hairlineStrong
    /// Healthy remaining quota uses the accent, which stays above 4.5:1 on the track in both appearances.
    static let barHealthy = MacColor.accent
    static let primaryText = MacColor.primary
    static let secondaryText = MacColor.muted
    static let accent = MacColor.accent
    static let selectionFill = MacColor.accentSoft
    static let hover = MacColor.hover
    /// MacDesignSystem has no warning token yet; this pairs the board's amber with a darker light variant.
    static let warning = adaptive(dark: (196, 161, 90), light: (154, 103, 0))
    static let critical = MacColor.destructive
    static let errorFill = MacColor.destructive.opacity(0.14)
    static let errorText = MacColor.destructive
    static let signInFill = MacColor.raised
    static let signInText = MacColor.muted

    static let sidebarWidth = CGFloat(UsageBoardLayout.sidebarWidth)

    private static func adaptive(dark: (Int, Int, Int), light: (Int, Int, Int)) -> Color {
        func color(_ rgb: (Int, Int, Int)) -> NSColor {
            NSColor(
                srgbRed: CGFloat(rgb.0) / 255,
                green: CGFloat(rgb.1) / 255,
                blue: CGFloat(rgb.2) / 255,
                alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? color(dark) : color(light)
        })
    }

    static func barFill(for tone: UsageBoardBarTone) -> Color {
        switch tone {
        case .healthy: self.barHealthy
        case .warning: self.warning
        case .critical: self.critical
        case .empty: self.track
        }
    }
}

struct UsageBoardScaledFont: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 13
    var role: UsageBoardMetrics.Role
    var weight: Font.Weight
    var digits: Bool

    func body(content: Content) -> some View {
        let size = UsageBoardMetrics.size(self.role) * self.bodySize / 13
        let font = Font.system(size: size, weight: self.weight)
        content.font(self.digits ? font.monospacedDigit() : font)
    }
}

extension View {
    func boardFont(
        _ role: UsageBoardMetrics.Role,
        weight: Font.Weight? = nil,
        digits: Bool? = nil) -> some View
    {
        modifier(UsageBoardScaledFont(
            role: role,
            weight: weight ?? UsageBoardMetrics.weight(role),
            digits: digits ?? UsageBoardMetrics.usesDigits(role)))
    }

    /// A card on the board: the design system's raised surface (soft halo and ring in light,
    /// solid fill and hairline in dark).
    func boardCard(radius: CGFloat = UsageBoardMetrics.radiusCard, fill: Color = UsageBoardTheme.card) -> some View {
        macSurface(radius: radius, fill: fill, elevation: .raised)
    }

    func boardHairline(radius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(UsageBoardTheme.hairline, lineWidth: UsageBoardMetrics.hairline))
    }
}

struct UsageBoardRowFrame: Equatable {
    var id: String
    var frame: CGRect
}

struct UsageBoardRowFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
