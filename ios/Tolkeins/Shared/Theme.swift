import SwiftUI
import UIKit

extension Color {
    static let tolkeinsBackground = Color(uiColor: .systemBackground)
    static let tolkeinsCard = Color(uiColor: .secondarySystemBackground)
    static let tolkeinsGrouped = Color(uiColor: .systemGroupedBackground)
    static let tolkeinsTrack = Color.primary.opacity(0.12)
}

enum MeterTone {
    case calm
    case nearLimit
    case atLimit

    var color: Color {
        switch self {
        case .calm:
            Color.primary.opacity(0.78)
        case .nearLimit:
            Color.orange.opacity(0.92)
        case .atLimit:
            Color.orange
        }
    }
}

func meterTone(usedPercent: Double) -> MeterTone {
    if usedPercent >= 95 { return .atLimit }
    if usedPercent >= 80 { return .nearLimit }
    return .calm
}

struct UsageMeter: View {
    var percent: Double
    @ScaledMetric(relativeTo: .body) private var barHeight = 7

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * CGFloat(min(max(percent, 0), 100) / 100)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.tolkeinsTrack)
                Capsule()
                    .fill(meterTone(usedPercent: percent).color)
                    .frame(width: max(percent > 0 ? 4 : 0, width))
            }
        }
        .frame(height: barHeight)
        .accessibilityHidden(true)
    }
}

struct SampleData {
    static func snapshot(now: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            schemaVersion: 1,
            generatedAt: now,
            services: [
                UsageService(
                    id: "claude",
                    name: "Claude",
                    plan: "Max",
                    windows: [
                        UsageWindow(label: "Session", usedPercent: 20, resetsAt: now.addingTimeInterval(80 * 60), windowMinutes: 300),
                        UsageWindow(label: "Weekly", usedPercent: 47, resetsAt: now.addingTimeInterval(18 * 3600), windowMinutes: 10080),
                        UsageWindow(label: "Fable only", usedPercent: 0, resetsAt: now.addingTimeInterval(18 * 3600), windowMinutes: 10080),
                    ],
                    pace: UsagePace(
                        primary: PaceSide(
                            stage: "farBehind",
                            willLastToReset: true,
                            expectedUsedPercent: 73,
                            deltaPercent: -53,
                            summary: "53% in reserve. Expected 73% used. Lasts until reset."
                        )
                    ),
                    credits: nil,
                    renewsOn: "2026-11-12",
                    price: PlanPrice(amount: 100, currency: "USD", interval: "month"),
                    source: "claude",
                    fetchedAt: now,
                    error: nil
                ),
                UsageService(
                    id: "codex",
                    name: "Codex",
                    plan: "Pro",
                    windows: [
                        UsageWindow(label: "Weekly", usedPercent: 44, resetsAt: now.addingTimeInterval(6 * 24 * 3600), windowMinutes: 10080),
                    ],
                    pace: UsagePace(
                        secondary: PaceSide(
                            stage: "farAhead",
                            willLastToReset: false,
                            expectedUsedPercent: 7,
                            deltaPercent: 37,
                            summary: "37% in deficit. Expected 7% used. Runs out in 14h 48m."
                        )
                    ),
                    credits: UsageCredits(remaining: 42789, currencyCode: "Credits"),
                    renewsOn: "2026-11-03",
                    price: PlanPrice(amount: 20, currency: "USD", interval: "month"),
                    source: "codex-cli",
                    fetchedAt: now,
                    error: nil
                ),
                UsageService(
                    id: "grok",
                    name: "Grok Bot",
                    plan: "SuperGrok",
                    windows: [
                        UsageWindow(label: "Weekly", usedPercent: 12, resetsAt: now.addingTimeInterval(3 * 24 * 3600), windowMinutes: 10080),
                    ],
                    pace: nil,
                    credits: nil,
                    renewsOn: "2026-11-20",
                    price: PlanPrice(amount: 30, currency: "USD", interval: "month"),
                    source: "manual",
                    fetchedAt: now,
                    error: nil
                ),
                UsageService(
                    id: "cursor",
                    name: "Cursor",
                    plan: "Pro",
                    windows: [],
                    pace: nil,
                    credits: nil,
                    renewsOn: "2026-11-01",
                    price: PlanPrice(amount: 20, currency: "USD", interval: "month"),
                    source: "cli",
                    fetchedAt: now,
                    error: UsageProblem(message: "No Cursor session found.", kind: "needs-sign-in")
                ),
                UsageService(
                    id: "warp",
                    name: "Warp",
                    plan: "Build",
                    windows: [],
                    pace: nil,
                    credits: nil,
                    renewsOn: "2026-11-15",
                    price: PlanPrice(amount: 20, currency: "USD", interval: "month"),
                    source: "api",
                    fetchedAt: now,
                    error: UsageProblem(message: "Add a Warp API key in CodexBar.", kind: "unavailable")
                ),
            ]
        )
    }
}
