import CodexBarCore
import InternalUI
import SwiftUI

/// Per-provider picker for the quota window behind the menu bar percent, as a settings row.
///
/// Writes a per-provider layout override so the choice survives whatever the global layout says,
/// which is also how the layout editor's provider scope persists. The Plugins pane embeds it too.
@MainActor
struct ProviderMenuBarPercentWindowSettingsView: View {
    let instanceID: ProviderInstanceID
    @Bindable var settings: SettingsStore
    var snapshot: UsageSnapshot?

    init(provider: UsageProvider, settings: SettingsStore, snapshot: UsageSnapshot? = nil) {
        self.init(instanceID: provider.instanceID, settings: settings, snapshot: snapshot)
    }

    init(instanceID: ProviderInstanceID, settings: SettingsStore, snapshot: UsageSnapshot? = nil) {
        self.instanceID = instanceID
        self.settings = settings
        self.snapshot = snapshot
    }

    var body: some View {
        self.picker
    }

    /// Whether the row shows: always for plugins, and for a provider only while the menu bar has a percent to steer.
    var isVisible: Bool {
        self.picker.isVisible
    }

    private var picker: ProviderMenuBarPercentWindowPicker {
        ProviderMenuBarPercentWindowPicker(
            provider: self.instanceID.firstPartyProvider,
            iconStyle: self.settings.menuBarIconStyle,
            layout: self.layoutBinding,
            metric: self.metricBinding,
            snapshot: self.snapshot)
    }

    var layoutBinding: Binding<MenuBarLayout> {
        Binding(
            get: {
                if let provider = self.instanceID.firstPartyProvider {
                    return self.settings.menuBarLayoutResolution(for: provider).layout
                }
                return self.settings.menuBarLayout(forPlugin: self.instanceID)
            },
            set: { self.settings.setMenuBarLayout($0, forInstanceID: self.instanceID) })
    }

    var metricBinding: Binding<MenuBarMetricPreference> {
        guard let provider = self.instanceID.firstPartyProvider else { return .constant(.automatic) }
        return Binding(
            get: { self.settings.menuBarMetricPreference(for: provider) },
            set: { self.settings.setMenuBarMetricPreference($0, for: provider) })
    }
}

@MainActor
struct ProviderMenuBarPercentWindowPicker: View {
    let provider: UsageProvider?
    let iconStyle: MenuBarIconStyle
    @Binding var layout: MenuBarLayout
    var metric: Binding<MenuBarMetricPreference> = .constant(.automatic)
    var snapshot: UsageSnapshot?

    var available: [MenuBarPercentWindowPreference] {
        if let provider {
            return MenuBarPercentWindowPreference.available(for: provider, layout: self.layout)
        }
        return MenuBarPercentWindowPreference.availableForPlugin(snapshot: self.snapshot, layout: self.layout)
    }

    /// Plugin settings always show the row (the choice also controls the switcher in meter mode); a provider shows it
    /// only while the icon style and layout have a percent the choice can change.
    var isVisible: Bool {
        self.provider == nil || MenuBarPercentWindowPreference.isVisible(
            iconStyle: self.iconStyle,
            layout: self.layout,
            available: self.available)
    }

    var body: some View {
        if self.isVisible {
            MacSettingsRow(L("menu_bar_metric_title"), subtitle: L("menu_bar_metric_subtitle")) {
                MacPopUpButton(self.options, selection: self.selectionBinding)
            }
        }
    }

    /// The pop-up's choices: Custom while mixed windows stay under the layout editor's control, then each window.
    var options: [(MenuBarPercentWindowPreference?, String)] {
        let custom: [(MenuBarPercentWindowPreference?, String)] = self.selectionBinding.wrappedValue == nil
            ? [(nil, L("menu_bar_layout_preset_custom"))]
            : []
        return custom + self.available.map { preference in
            (preference, preference.label(for: self.provider, snapshot: self.snapshot))
        }
    }

    var selectionBinding: Binding<MenuBarPercentWindowPreference?> {
        Binding(
            get: {
                let metric = self.available.contains(.monthlyPlan) ? self.metric.wrappedValue : nil
                return MenuBarPercentWindowPreference.current(in: self.layout, metric: metric)
                    .flatMap { self.available.contains($0) ? $0 : nil }
            },
            set: { preference in
                let layout = self.layout
                guard let preference, self.available.contains(preference) else { return }
                let updated = preference.applied(to: layout)
                if let provider = self.provider,
                   MenuBarPercentWindowPreference.available(for: provider).contains(.monthlyPlan)
                {
                    self.metric.wrappedValue = preference.menuBarMetric
                    // Without a percentage to change, only the metric is stored, so the layout keeps following
                    // its source instead of becoming a provider override.
                    guard MenuBarPercentWindowPreference.hasPercentToken(in: layout) else { return }
                }
                self.layout = updated
            })
    }
}
