import Foundation

func ageText(_ date: Date, now: Date = Date()) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: now)
}

func percentText(_ value: Double) -> String {
    if abs(value.rounded() - value) < 0.05 {
        return "\(Int(value.rounded()))%"
    }
    return String(format: "%.1f%%", value)
}

func quotaStatus(usedPercent: Double) -> String {
    if usedPercent >= 95 { return "At limit" }
    if usedPercent >= 80 { return "Near limit" }
    return "In budget"
}

func problemStatus(kind: String) -> String {
    if kind == "needs-sign-in" { return "Needs sign-in" }
    return "Unavailable"
}

func resetAccessibility(resetsAt: Date?, now: Date) -> String {
    guard let resetsAt else { return "Reset time unknown" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    let relative = formatter.localizedString(for: resetsAt, relativeTo: now)
    if resetsAt <= now {
        return "Reset \(relative)"
    }
    return "Resets \(relative)"
}

func renewalDate(_ day: String) -> Date? {
    let parts = day.split(separator: "-")
    guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let dayNumber = Int(parts[2]) else {
        return nil
    }
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = dayNumber
    return Calendar.current.date(from: components)
}

func renewalText(_ day: String) -> String? {
    guard let date = renewalDate(day) else { return nil }
    return "Renews \(date.formatted(.dateTime.month(.abbreviated).day()))"
}

func priceText(_ price: PlanPrice) -> String? {
    guard price.interval == "month" || price.interval == "year" else { return nil }
    let fractionDigits = price.amount.rounded() == price.amount ? 0 : 2
    let amount = price.amount.formatted(
        .currency(code: price.currency).precision(.fractionLength(fractionDigits))
    )
    let period = price.interval == "year" ? "year" : "month"
    return "\(amount) / \(period)"
}

func creditsText(_ credits: UsageCredits) -> String {
    let number = credits.remaining.formatted(.number.precision(.fractionLength(0)))
    let unit = credits.currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines)
    if unit == nil || unit?.caseInsensitiveCompare("credits") == .orderedSame {
        return "\(number) credits left"
    }
    return "\(number) \(unit ?? "credits") left"
}

func paceSummary(pace: UsagePace?, label: String) -> String? {
    let side: PaceSide?
    switch label.lowercased() {
    case "session":
        side = pace?.primary ?? pace?.secondary
    case "weekly":
        side = pace?.secondary ?? pace?.primary
    default:
        side = pace?.primary ?? pace?.secondary
    }
    guard let summary = side?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty else {
        return nil
    }
    return summary
}

func windowAccessibility(serviceName: String, window: UsageWindow, now: Date) -> String {
    [
        "\(serviceName), \(window.label)",
        "\(percentText(window.usedPercent)) used",
        quotaStatus(usedPercent: window.usedPercent),
        resetAccessibility(resetsAt: window.resetsAt, now: now),
    ].joined(separator: ", ")
}

func shortWindowLabel(_ window: UsageWindow) -> String {
    switch window.label.lowercased() {
    case "weekly":
        return "Wk"
    case "session":
        return "Sess"
    case "monthly":
        return "Mo"
    default:
        if let minutes = window.windowMinutes, minutes > 0, minutes < 60 * 48, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)h"
        }
        return String(window.label.prefix(4))
    }
}
