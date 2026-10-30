import CodexBarCore
import SwiftUI

/// Deliberate dark palette. Text pairs below are WCAG AA on the surfaces they sit on
/// (primary #F4F6FB is about 14:1 on cards; secondary #C5CEDB is about 10:1).
enum UsageBoardTheme {
    static let canvas = Color(red: 16 / 255, green: 18 / 255, blue: 24 / 255)
    static let sidebar = Color(red: 23 / 255, green: 26 / 255, blue: 34 / 255)
    static let card = Color(red: 30 / 255, green: 34 / 255, blue: 44 / 255)
    static let cardRaised = Color(red: 37 / 255, green: 42 / 255, blue: 54 / 255)
    static let selectedRow = Color(red: 42 / 255, green: 51 / 255, blue: 70 / 255)
    static let separator = Color(red: 52 / 255, green: 58 / 255, blue: 72 / 255)
    static let track = Color(red: 50 / 255, green: 56 / 255, blue: 70 / 255)
    static let primaryText = Color(red: 244 / 255, green: 246 / 255, blue: 251 / 255)
    static let secondaryText = Color(red: 197 / 255, green: 206 / 255, blue: 219 / 255)
    static let accent = Color(red: 158 / 255, green: 190 / 255, blue: 255 / 255)
    static let warning = Color(red: 246 / 255, green: 212 / 255, blue: 138 / 255)
    static let critical = Color(red: 255 / 255, green: 176 / 255, blue: 164 / 255)
    static let errorFill = Color(red: 60 / 255, green: 36 / 255, blue: 40 / 255)
    static let errorText = Color(red: 255 / 255, green: 215 / 255, blue: 209 / 255)
    static let signInFill = Color(red: 36 / 255, green: 48 / 255, blue: 68 / 255)
    static let signInText = Color(red: 217 / 255, green: 231 / 255, blue: 255 / 255)

    static let sidebarWidth = CGFloat(UsageBoardLayout.sidebarWidth)
    static let cornerRadius: CGFloat = 14
    static let cardRadius: CGFloat = 12

    static let percentFont = Font.system(size: 22, weight: .semibold).monospacedDigit()
    static let percentCompactFont = Font.system(size: 15, weight: .semibold).monospacedDigit()
    static let titleFont = Font.system(size: 15, weight: .semibold)
    static let bodyFont = Font.system(size: 13, weight: .regular)
    static let captionFont = Font.system(size: 12, weight: .regular).monospacedDigit()
    static let labelFont = Font.system(size: 11, weight: .medium)

    static func fill(for percent: Double) -> Color {
        if percent >= 90 { return self.critical }
        if percent >= 70 { return self.warning }
        return self.accent
    }

    static func percentColor(for percent: Double?) -> Color {
        guard let percent else { return self.primaryText }
        return self.fill(for: percent)
    }
}
