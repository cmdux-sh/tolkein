import Foundation

/// Windows closest to their limit lead. A reset inside two hours adds weight
/// only when usage is already at least half, so a quiet session that is about
/// to reset does not hide a fuller weekly pool. Sign-in problems stay visible
/// and sort after any live window.
let staleAfter: TimeInterval = 30 * 60

struct AttentionItem: Identifiable, Equatable {
    var id: String
    var serviceID: String
    var windowLabel: String?
    var score: Double
    var resetsAt: Date?
}

func isStale(generatedAt: Date, now: Date = Date()) -> Bool {
    now.timeIntervalSince(generatedAt) > staleAfter
}

func urgencyScore(percent: Double, resetsAt: Date?, now: Date) -> Double {
    var score = percent
    if let resetsAt {
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining >= 0, remaining <= 2 * 60 * 60, percent >= 50 {
            score += 15
        }
    }
    return score
}

func orderedServices(_ snapshot: UsageSnapshot, now: Date) -> [UsageService] {
    snapshot.services.sorted { lhs, rhs in
        let left = serviceScore(lhs, now: now)
        let right = serviceScore(rhs, now: now)
        if left != right { return left > right }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

func orderedWindows(_ service: UsageService, now: Date) -> [UsageWindow] {
    service.windows.sorted { lhs, rhs in
        compareAttention(
            leftScore: urgencyScore(percent: lhs.usedPercent, resetsAt: lhs.resetsAt, now: now),
            rightScore: urgencyScore(percent: rhs.usedPercent, resetsAt: rhs.resetsAt, now: now),
            leftReset: lhs.resetsAt,
            rightReset: rhs.resetsAt,
            leftID: lhs.label,
            rightID: rhs.label
        )
    }
}

func attentionItems(snapshot: UsageSnapshot, now: Date) -> [AttentionItem] {
    var items: [AttentionItem] = []
    for service in snapshot.services {
        if service.windows.isEmpty {
            items.append(
                AttentionItem(
                    id: service.id,
                    serviceID: service.id,
                    windowLabel: nil,
                    score: service.error?.kind == "needs-sign-in" ? -1 : -2,
                    resetsAt: nil
                )
            )
            continue
        }
        for window in service.windows {
            items.append(
                AttentionItem(
                    id: "\(service.id).\(window.label)",
                    serviceID: service.id,
                    windowLabel: window.label,
                    score: urgencyScore(percent: window.usedPercent, resetsAt: window.resetsAt, now: now),
                    resetsAt: window.resetsAt
                )
            )
        }
    }
    return items.sorted { lhs, rhs in
        compareAttention(
            leftScore: lhs.score,
            rightScore: rhs.score,
            leftReset: lhs.resetsAt,
            rightReset: rhs.resetsAt,
            leftID: lhs.id,
            rightID: rhs.id
        )
    }
}

func service(id: String, in snapshot: UsageSnapshot) -> UsageService? {
    snapshot.services.first { $0.id == id }
}

func window(labeled label: String, in service: UsageService) -> UsageWindow? {
    service.windows.first { $0.label == label }
}

private func serviceScore(_ service: UsageService, now: Date) -> Double {
    let best = service.windows
        .map { urgencyScore(percent: $0.usedPercent, resetsAt: $0.resetsAt, now: now) }
        .max()
    if let best { return best }
    if service.error?.kind == "needs-sign-in" { return -1 }
    return -2
}

private func compareAttention(
    leftScore: Double,
    rightScore: Double,
    leftReset: Date?,
    rightReset: Date?,
    leftID: String,
    rightID: String
) -> Bool {
    if leftScore != rightScore { return leftScore > rightScore }
    switch (leftReset, rightReset) {
    case let (left?, right?):
        if left != right { return left < right }
    case (.some, nil):
        return true
    case (nil, .some):
        return false
    case (nil, nil):
        break
    }
    return leftID < rightID
}
