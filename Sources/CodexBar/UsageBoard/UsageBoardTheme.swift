import CodexBarCore
import SwiftUI

/// Fluid Functionalism tokens for the usage board, mapped onto macOS.
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
    static let radiusCard: CGFloat = 8
    static let radiusItem: CGFloat = 6
    static let hairline: CGFloat = 1
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

/// Near-black floor, one step of elevation, hairline borders.
/// Primary `#F4F4F5` on `#1A1A1A` is about 16:1. Muted `#A3A3A3` on the same card is about 6.9:1.
enum UsageBoardTheme {
    static let canvas = Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255)
    static let surface = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
    static let card = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    static let cardRaised = Color(red: 32 / 255, green: 32 / 255, blue: 32 / 255)
    static let hairline = Color(red: 46 / 255, green: 46 / 255, blue: 46 / 255)
    static let track = Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
    static let bar = Color(red: 168 / 255, green: 168 / 255, blue: 168 / 255)
    /// Healthy remaining quota. Blue on the near-black track stays above 4.5:1.
    static let barHealthy = Color(red: 107 / 255, green: 151 / 255, blue: 255 / 255)
    static let primaryText = Color(red: 244 / 255, green: 244 / 255, blue: 245 / 255)
    static let secondaryText = Color(red: 163 / 255, green: 163 / 255, blue: 163 / 255)
    static let accent = Color(red: 107 / 255, green: 151 / 255, blue: 255 / 255)
    static let selectionFill = Color(red: 107 / 255, green: 151 / 255, blue: 255 / 255).opacity(0.16)
    static let hover = Color.white.opacity(0.06)
    static let warning = Color(red: 196 / 255, green: 161 / 255, blue: 90 / 255)
    static let critical = Color(red: 210 / 255, green: 123 / 255, blue: 114 / 255)
    static let errorFill = Color(red: 42 / 255, green: 22 / 255, blue: 24 / 255)
    static let errorText = Color(red: 240 / 255, green: 180 / 255, blue: 174 / 255)
    static let signInFill = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    static let signInText = Color(red: 163 / 255, green: 163 / 255, blue: 163 / 255)

    static let sidebarWidth = CGFloat(UsageBoardLayout.sidebarWidth)

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
