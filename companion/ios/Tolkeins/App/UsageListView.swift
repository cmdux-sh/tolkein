import SwiftUI

struct UsageListView: View {
    @Bindable var model: UsageModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if AppIdentity.hasPlaceholderIdentity {
                        NoticeBanner(
                            text: "This build still uses the PLACEHOLDER team ID and App Group. Replace them in ios/Config/Shared.xcconfig, then run it again."
                        )
                    }
                    if let message = model.statusMessage {
                        NoticeBanner(text: message)
                    }
                    if let snapshot = model.snapshot {
                        if isStale(generatedAt: snapshot.generatedAt) {
                            NoticeBanner(
                                text: "Updated \(ageText(snapshot.generatedAt)). The collector may be paused."
                            )
                            .accessibilityLabel("Data is stale. Updated \(ageText(snapshot.generatedAt)).")
                        }
                        ForEach(orderedServices(snapshot, now: Date())) { service in
                            ServiceCard(service: service)
                        }
                    } else if model.isReady {
                        EmptyState(
                            title: "No snapshot yet",
                            message: "The collector publishes within about 10 minutes of a successful run."
                        )
                    } else {
                        EmptyState(
                            title: "Tolkeins",
                            message: "Usage, reset times, and renewal dates for the assistants you pay for. The Mac publishes the numbers. This phone keeps only a read token."
                        )
                        Button("Add worker") { showSettings = true }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.tolkeinsGrouped)
            .navigationTitle("Tolkeins")
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(model: model)
            }
            .overlay {
                if model.isLoading && model.snapshot == nil {
                    ProgressView("Loading usage")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}

private struct ServiceCard: View {
    var service: UsageService
    private var now: Date { Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if service.windows.isEmpty, let error = service.error {
                ProblemBlock(error: error)
            } else {
                let windows = orderedWindows(service, now: now)
                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                    WindowBlock(service: service, window: window, showsPace: index == 0)
                }
            }
            if let credits = service.credits {
                Text(creditsText(credits))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tolkeinsCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.headline)
                if let plan = service.plan {
                    Text(plan)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let renewsOn = service.renewsOn, let text = renewalText(renewsOn) {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let price = service.price, let text = priceText(price) {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

private struct WindowBlock: View {
    var service: UsageService
    var window: UsageWindow
    var showsPace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(window.label)
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Text(quotaStatus(usedPercent: window.usedPercent))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(percentText(window.usedPercent))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.label)
                        .font(.subheadline)
                    Text(quotaStatus(usedPercent: window.usedPercent))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(percentText(window.usedPercent))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
            }
            UsageMeter(percent: window.usedPercent)
            ResetLine(resetsAt: window.resetsAt)
            if showsPace, let summary = paceSummary(pace: service.pace, label: window.label) {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(windowAccessibility(serviceName: service.name, window: window, now: Date()))
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
            .font(.footnote)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        } else {
            Text("Reset time unknown")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProblemBlock: View {
    var error: UsageProblem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(problemStatus(kind: error.kind))
                .font(.headline)
            Text(error.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NoticeBanner: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.tolkeinsCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct EmptyState: View {
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Usage") {
    UsageListView(model: PreviewUsage.ready)
}

#Preview("Stale") {
    UsageListView(model: PreviewUsage.stale)
}

#Preview("Dark") {
    UsageListView(model: PreviewUsage.ready)
        .preferredColorScheme(.dark)
}

@MainActor
private enum PreviewUsage {
    static var ready: UsageModel {
        let model = UsageModel()
        model.snapshot = SampleData.snapshot()
        model.workerURL = "https://tolkeins.example.workers.dev"
        model.hasToken = true
        return model
    }

    static var stale: UsageModel {
        let model = UsageModel()
        var snapshot = SampleData.snapshot(now: Date().addingTimeInterval(-2 * 60 * 60))
        snapshot.generatedAt = Date().addingTimeInterval(-2 * 60 * 60)
        model.snapshot = snapshot
        model.workerURL = "https://tolkeins.example.workers.dev"
        model.hasToken = true
        return model
    }
}
