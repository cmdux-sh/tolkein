import CodexBarCore
import Foundation

struct ProviderAccountUsageOverview {
    struct Row: Identifiable {
        let id: String
        let title: String
        let isFollowed: Bool
        let isSystem: Bool
        let model: UsageMenuCardView.Model
        let usageItems: [ProviderUsageItemDescriptor]
        let updatedAt: Date?
        let sourceLabel: String?
        let error: String?
        let isRefreshing: Bool
    }

    let rows: [Row]
    let refreshLimit: Int
    let canRefresh: Bool
    let onRefresh: (Set<String>) -> Void

    var usageItems: [ProviderUsageItemDescriptor] {
        // Shared controls must keep a real quota visible regardless of account ordering.
        self.rows.flatMap(\.usageItems).reduce(into: []) { items, item in
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                if items[index].requiresOptionalUsage, !item.requiresOptionalUsage {
                    items[index] = item
                }
            } else {
                items.append(item)
            }
        }
    }
}
