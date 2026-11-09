import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

/// One provider's Settings page. The title row carries the provider's name, its detail line, Refresh and the
/// Enabled switch; under it come the fixed sections (`ProviderSettingsPageSection`), each left out when it has
/// nothing to show for this provider.
@MainActor
struct ProviderSettingsPage: View {
    @Bindable var model: ProviderSettingsPageModel

    var body: some View {
        let content = self.model.pageContent()
        IUSettingsPage(content.displayName, subtitle: Self.headerSubtitle(content.subtitle)) {
            HStack(spacing: IUSpace.unit * 2) {
                IUToolButton(L("Refresh"), systemImage: "arrow.clockwise") {
                    self.model.refresh()
                }
                Toggle(L("Enabled"), isOn: self.model.binding(for: self.model.provider))
                    .toggleStyle(.iuSwitch)
                    .labelsHidden()
                    .help(L("Enabled"))
            }
        } content: {
            ProviderSettingsPageSections(model: self.model, content: content)
        }
        .background(ProviderSettingsFocusResigner())
        // While a confirmation is open, keyboard and VoiceOver stay on it, as on the other panes.
        .disabled(self.model.activeConfirmation != nil)
        .accessibilityHidden(self.model.activeConfirmation != nil)
        .overlay {
            if let confirmation = self.model.activeConfirmation {
                ProviderSettingsConfirmationOverlay(
                    confirmation: confirmation,
                    onConfirm: { self.model.confirmActiveConfirmation() },
                    onCancel: { self.model.dismissActiveConfirmation() })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.model.runSettingsDidBecomeActiveHooks()
        }
    }

    /// The detail line and the last-fetch line, joined into one subtitle line.
    static func headerSubtitle(_ subtitle: String) -> String {
        let lines = subtitle.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 else { return subtitle }
        let first = lines[0]
        let tail = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? String(first) : "\(first) • \(tail)"
    }
}

/// The page's sections in order. Each group is marked as its search entry's destination.
@MainActor
struct ProviderSettingsPageSections: View {
    let model: ProviderSettingsPageModel
    let content: ProviderSettingsPageContent

    var body: some View {
        let provider = self.content.provider
        let isEnabled = self.model.binding(for: provider).wrappedValue
        ForEach(self.content.sections) { section in
            ProviderSettingsSectionGroup(id: section.searchEntryID(for: provider)) {
                switch section {
                case .status:
                    ProviderStatusSection(
                        facts: self.content.statusFacts,
                        errorDisplay: self.content.errorDisplay,
                        isErrorExpanded: Bindable(self.model).isErrorExpanded,
                        onCopyError: { self.model.copyToPasteboard($0) })
                case .usage:
                    ProviderUsageSections(
                        content: self.content,
                        settings: self.model.settings,
                        isEnabled: isEnabled,
                        isRefreshing: self.model.isRefreshing)
                case .connection:
                    ProviderConnectionSections(content: self.content, model: self.model)
                case .display:
                    ProviderDisplaySection(
                        content: self.content,
                        settings: self.model.settings,
                        store: self.model.store)
                case .alerts:
                    ProviderQuotaWarningSettingsView(provider: provider, settings: self.model.settings)
                case .options:
                    IUSettingsSection(ProviderSettingsPageSection.options.title) {
                        ForEach(self.content.toggles) { toggle in
                            ProviderSettingsToggleRows(toggle: toggle)
                        }
                    }
                }
            }
        }
    }
}

/// One page section's views, spaced like the page's sections and marked as a search destination.
private struct ProviderSettingsSectionGroup<Content: View>: View {
    let id: String?
    @ViewBuilder let content: Content

    var body: some View {
        let group = VStack(alignment: .leading, spacing: IUSpace.settingsSectionGap) { self.content }
            .frame(maxWidth: .infinity, alignment: .leading)
        if let id {
            group.settingsAnchor(id)
        } else {
            group
        }
    }
}

/// Menu bar metric, menu-bar placement pickers and the accent colour.
@MainActor
struct ProviderDisplaySection: View {
    let content: ProviderSettingsPageContent
    let settings: SettingsStore
    let store: UsageStore

    var body: some View {
        IUSettingsSection(ProviderSettingsPageSection.display.title) {
            if self.content.showsMenuBarMetric {
                ProviderMenuBarPercentWindowSettingsView(
                    provider: self.content.provider,
                    settings: self.settings,
                    snapshot: self.store.snapshot(for: self.content.provider.instanceID))
            }
            ForEach(self.content.menuBarPickers) { picker in
                ProviderSettingsPickerRow(picker: picker)
            }
            ProviderAccentColorSettingsView(provider: self.content.provider, settings: self.settings)
        }
    }
}

/// A confirmation over the page: the scrim dims the page and the alert asks before a destructive action.
struct ProviderSettingsConfirmationOverlay: View {
    let confirmation: ProviderSettingsConfirmationState
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            IUColor.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: self.onCancel)
                .accessibilityHidden(true)
            IUAlert(
                self.confirmation.title,
                message: self.confirmation.message,
                primary: (self.confirmation.confirmTitle, self.onConfirm),
                secondary: (L("cancel"), self.onCancel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onExitCommand(perform: self.onCancel)
    }
}
