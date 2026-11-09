import CodexBarCore
import InternalUI
import SwiftUI

/// The statistics time zone, as two settings rows for Settings → Costs: the pinned zone, and a button that pins
/// the Mac's current zone. Daily buckets use this zone, so changing it can move usage to a different day.
@MainActor
struct SpendTimeZoneControls: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        IUSettingsRow(
            L("Statistics time zone"),
            subtitle: L("Daily usage uses a fixed time zone. Changing it may move usage to a different day."))
        {
            IUPopUpButton(self.timeZoneIdentifiers.map { ($0, $0) }, selection: self.timeZoneBinding)
                .help(self.selectedIdentifier)
                .accessibilityLabel(L("Statistics time zone"))
                .accessibilityIdentifier("spend-time-zone-picker")
        }
        .settingsAnchor(CostsSettingsPane.Anchor.timeZone)
        IUSettingsRow(L("Use Mac's current time zone"), subtitle: TimeZone.current.identifier) {
            Button(L("apply")) {
                self.useCurrentTimeZone()
            }
            .buttonStyle(.iu())
            .help(TimeZone.current.identifier)
            .accessibilityIdentifier("spend-use-current-time-zone")
        }
        .settingsAnchor(CostsSettingsPane.Anchor.useCurrentTimeZone)
    }

    var selectedIdentifier: String {
        let storedIdentifier = self.settings.costUsageBucketTimeZoneIdentifier
        return CostUsageBucketTimeZone.isValidIdentifier(storedIdentifier)
            ? storedIdentifier
            : self.settings.costUsageBucketCalendar.timeZone.identifier
    }

    var timeZoneIdentifiers: [String] {
        // Include stored aliases and fixed offsets, which may be absent from Foundation's catalog.
        Array(Set(TimeZone.knownTimeZoneIdentifiers + [self.selectedIdentifier, TimeZone.current.identifier, "UTC"]))
            .sorted()
    }

    var timeZoneBinding: Binding<String> {
        Binding(
            get: { self.selectedIdentifier },
            set: { self.settings.costUsageBucketTimeZoneIdentifier = $0 })
    }

    func useCurrentTimeZone(_ timeZone: TimeZone = .current) {
        self.settings.costUsageBucketTimeZoneIdentifier = timeZone.identifier
    }
}
