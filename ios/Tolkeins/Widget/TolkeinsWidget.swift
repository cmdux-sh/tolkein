import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    var date: Date
    var snapshot: UsageSnapshot?
    var message: String?
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: SampleData.snapshot(), message: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: Date(), snapshot: SampleData.snapshot(), message: nil))
            return
        }
        completion(UsageEntry(date: Date(), snapshot: SnapshotStore.load(), message: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let next = Date().addingTimeInterval(20 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func loadEntry() async -> UsageEntry {
        let url = AppSettings.workerURL
        let token = try? SecretStore.loadToken()
        guard !url.isEmpty, let token, !token.isEmpty else {
            return UsageEntry(
                date: Date(),
                snapshot: SnapshotStore.load(),
                message: SnapshotStore.load() == nil ? "Open Tolkeins to add the worker and read token." : nil
            )
        }
        do {
            let snapshot = try await UsageClient.fetchUsage(baseURL: url, token: token)
            try? SnapshotStore.save(snapshot)
            return UsageEntry(date: Date(), snapshot: snapshot, message: nil)
        } catch {
            if let cached = SnapshotStore.load() {
                return UsageEntry(date: Date(), snapshot: cached, message: nil)
            }
            return UsageEntry(date: Date(), snapshot: nil, message: "Couldn't refresh.")
        }
    }
}

struct TolkeinsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall:
                    SmallUsage(snapshot: snapshot)
                case .systemMedium:
                    MediumUsage(snapshot: snapshot)
                case .accessoryCircular:
                    CircularUsage(snapshot: snapshot)
                case .accessoryRectangular:
                    RectangularUsage(snapshot: snapshot)
                case .accessoryInline:
                    InlineUsage(snapshot: snapshot)
                default:
                    LargeUsage(snapshot: snapshot)
                }
            } else {
                Text(entry.message ?? "No snapshot yet")
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "tolkeins://usage"))
    }
}

private struct SmallUsage: View {
    var snapshot: UsageSnapshot

    var body: some View {
        let now = Date()
        let item = attentionItems(snapshot: snapshot, now: now).first
        VStack(alignment: .leading, spacing: 6) {
            staleLine(snapshot)
            if let item, let service = service(id: item.serviceID, in: snapshot) {
                if let label = item.windowLabel, let window = window(labeled: label, in: service) {
                    ViewThatFits(in: .vertical) {
                        smallFull(service: service, window: window)
                        smallCompact(service: service, window: window)
                    }
                } else {
                    problem(service)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(snapshot, limit: 1))
    }

    private func smallFull(service: UsageService, window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(service.name)
                .font(.headline)
            Text(window.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(percentText(window.usedPercent))
                .font(.largeTitle.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(quotaStatus(usedPercent: window.usedPercent))
                .font(.caption)
                .foregroundStyle(.secondary)
            UsageMeter(percent: window.usedPercent)
            ResetLine(resetsAt: window.resetsAt)
            if let renewsOn = service.renewsOn, let text = renewalText(renewsOn) {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func smallCompact(service: UsageService, window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(service.name)
                .font(.headline)
            Text(percentText(window.usedPercent))
                .font(.title.weight(.semibold).monospacedDigit())
            Text(quotaStatus(usedPercent: window.usedPercent))
                .font(.caption)
                .foregroundStyle(.secondary)
            ResetLine(resetsAt: window.resetsAt)
        }
    }

    private func problem(_ service: UsageService) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(service.name)
                .font(.headline)
            Text(problemStatus(kind: service.error?.kind ?? "unavailable"))
                .font(.title3.weight(.semibold))
        }
    }
}

private struct MediumUsage: View {
    var snapshot: UsageSnapshot

    var body: some View {
        let items = Array(attentionItems(snapshot: snapshot, now: Date()).prefix(3))
        VStack(alignment: .leading, spacing: 8) {
            staleLine(snapshot)
            ForEach(items) { item in
                if let service = service(id: item.serviceID, in: snapshot) {
                    MediumRow(service: service, item: item)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(snapshot, limit: 3))
    }
}

private struct MediumRow: View {
    var service: UsageService
    var item: AttentionItem

    var body: some View {
        if let label = item.windowLabel, let window = window(labeled: label, in: service) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(service.name)
                        .font(.subheadline.weight(.semibold))
                    Text(window.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(quotaStatus(usedPercent: window.usedPercent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(percentText(window.usedPercent))
                        .font(.headline.monospacedDigit())
                }
                UsageMeter(percent: window.usedPercent)
                ResetLine(resetsAt: window.resetsAt)
            }
        } else {
            HStack {
                Text(service.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(problemStatus(kind: service.error?.kind ?? "unavailable"))
                    .font(.subheadline)
            }
        }
    }
}

private struct LargeUsage: View {
    var snapshot: UsageSnapshot

    var body: some View {
        let services = orderedServices(snapshot, now: Date())
        VStack(alignment: .leading, spacing: 8) {
            staleLine(snapshot)
            ForEach(services) { service in
                LargeServiceRow(service: service)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(snapshot, limit: 8))
    }
}

private struct LargeServiceRow: View {
    var service: UsageService

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(service.name)
                    .font(.subheadline.weight(.semibold))
                if let plan = service.plan {
                    Text(plan)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let renewsOn = service.renewsOn, let text = renewalText(renewsOn) {
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if service.windows.isEmpty {
                Text(problemStatus(kind: service.error?.kind ?? "unavailable"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(orderedWindows(service, now: Date()).prefix(2))) { window in
                    HStack(spacing: 6) {
                        Text(window.label)
                            .font(.caption2)
                            .frame(width: 64, alignment: .leading)
                        UsageMeter(percent: window.usedPercent)
                        Text(quotaStatus(usedPercent: window.usedPercent))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(percentText(window.usedPercent))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }
}

private struct CircularUsage: View {
    var snapshot: UsageSnapshot

    var body: some View {
        let now = Date()
        if let item = attentionItems(snapshot: snapshot, now: now).first,
           let service = service(id: item.serviceID, in: snapshot),
           let label = item.windowLabel,
           let window = window(labeled: label, in: service) {
            VStack(spacing: 0) {
                Text(percentText(window.usedPercent))
                    .font(.headline.weight(.semibold).monospacedDigit())
                    .widgetAccentable()
                Text(shortWindowLabel(window))
                    .font(.caption2)
            }
            .accessibilityLabel(windowAccessibility(serviceName: service.name, window: window, now: now))
        } else if let service = snapshot.services.first {
            Text(problemStatus(kind: service.error?.kind ?? "unavailable"))
                .font(.caption2)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("\(service.name), \(problemStatus(kind: service.error?.kind ?? "unavailable"))")
        }
    }
}

private struct RectangularUsage: View {
    var snapshot: UsageSnapshot

    var body: some View {
        let now = Date()
        if let item = attentionItems(snapshot: snapshot, now: now).first,
           let service = service(id: item.serviceID, in: snapshot) {
            if let label = item.windowLabel, let window = window(labeled: label, in: service) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(service.name) · \(window.label)")
                        .font(.headline)
                        .widgetAccentable()
                    Text("\(percentText(window.usedPercent)) \(quotaStatus(usedPercent: window.usedPercent))")
                        .font(.caption.monospacedDigit())
                    ResetLine(resetsAt: window.resetsAt)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(windowAccessibility(serviceName: service.name, window: window, now: now))
            } else {
                Text("\(service.name) \(problemStatus(kind: service.error?.kind ?? "unavailable"))")
                    .font(.headline)
            }
        }
    }
}

private struct InlineUsage: View {
    var snapshot: UsageSnapshot

    var body: some View {
        let now = Date()
        if let item = attentionItems(snapshot: snapshot, now: now).first,
           let service = service(id: item.serviceID, in: snapshot),
           let label = item.windowLabel,
           let window = window(labeled: label, in: service) {
            Text("\(service.name) \(percentText(window.usedPercent)) \(window.label)")
        } else if let service = snapshot.services.first {
            Text("\(service.name) \(problemStatus(kind: service.error?.kind ?? "unavailable"))")
        } else {
            Text("Tolkeins")
        }
    }
}

private struct ResetLine: View {
    var resetsAt: Date?

    var body: some View {
        if let resetsAt {
            HStack(spacing: 4) {
                Text("Resets")
                Text(resetsAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        } else {
            Text("Reset time unknown")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

@ViewBuilder
private func staleLine(_ snapshot: UsageSnapshot) -> some View {
    if isStale(generatedAt: snapshot.generatedAt) {
        Text("Updated \(ageText(snapshot.generatedAt))")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

private func summary(_ snapshot: UsageSnapshot, limit: Int) -> String {
    let now = Date()
    var parts: [String] = []
    if isStale(generatedAt: snapshot.generatedAt, now: now) {
        parts.append("Data is stale. Updated \(ageText(snapshot.generatedAt, now: now)).")
    }
    for item in attentionItems(snapshot: snapshot, now: now).prefix(limit) {
        guard let service = service(id: item.serviceID, in: snapshot) else { continue }
        if let label = item.windowLabel, let window = window(labeled: label, in: service) {
            parts.append(windowAccessibility(serviceName: service.name, window: window, now: now))
        } else {
            parts.append("\(service.name), \(problemStatus(kind: service.error?.kind ?? "unavailable"))")
        }
    }
    return parts.joined(separator: ". ")
}

struct TolkeinsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TolkeinsUsage", provider: UsageTimelineProvider()) { entry in
            TolkeinsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.tolkeinsBackground
                }
        }
        .configurationDisplayName("Tolkeins")
        .description("Usage, reset times, and renewal dates.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

@main
struct TolkeinsWidgetBundle: WidgetBundle {
    var body: some Widget {
        TolkeinsWidget()
    }
}
