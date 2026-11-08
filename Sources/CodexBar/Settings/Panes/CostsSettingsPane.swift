import SwiftUI

/// Costs: local estimated spend across providers.
/// Shows the old `SpendDashboardPane` (Usage & Spend) until the Internal UI rebuild replaces this file.
@MainActor
struct CostsSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        SpendDashboardPane(settings: self.context.settings, store: self.context.store)
    }
}

extension CostsSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.costs
        let usageAndSpend = L("tab_usage_spend")
        return [
            .paneTitle(pane, keywords: usageAndSpend),
            pane.searchEntry("dailySpend", L("Daily estimated spend"), keywords: usageAndSpend),
            pane.searchEntry("sessions", L("Sessions"), keywords: usageAndSpend),
        ]
    }
}
