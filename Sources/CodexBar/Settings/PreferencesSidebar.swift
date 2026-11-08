import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

/// The provider list's filter chips: every provider, or only the enabled ones (stored as `providersEnabledOnly`).
enum SettingsSidebarProviderFilter: Hashable, CaseIterable {
    case all
    case enabled

    init(enabledOnly: Bool) {
        self = enabledOnly ? .enabled : .all
    }

    var enabledOnly: Bool {
        self == .enabled
    }

    var title: String {
        switch self {
        case .all: L("All")
        case .enabled: L("Enabled")
        }
    }

    static var chips: [MacFilterChip<Self>] {
        self.allCases.map { MacFilterChip($0.title, id: $0) }
    }

    /// Dragging a provider edits the custom order, so it works only while that order is showing in full:
    /// not sorted A–Z and not filtered to the enabled providers.
    static func allowsReordering(sortedAlphabetically: Bool, filter: Self) -> Bool {
        !sortedAlphabetically && filter == .all
    }
}

/// What a provider row shows after its name: a spinner while it refreshes, otherwise a status symbol for a failed
/// refresh or a service incident, with its text as the tooltip. Healthy providers show nothing.
struct SettingsSidebarProviderStatus: Equatable {
    let tone: MacStatusTone
    let text: String

    static func resolve(
        isEnabled: Bool,
        isRefreshing: Bool,
        error: String?,
        statusChecksEnabled: Bool,
        indicator: ProviderStatusIndicator?) -> SettingsSidebarProviderStatus?
    {
        if isRefreshing { return SettingsSidebarProviderStatus(tone: .busy, text: L("Refreshing")) }
        guard isEnabled else { return nil }
        if let error { return SettingsSidebarProviderStatus(tone: .error, text: error) }
        guard statusChecksEnabled, let tone = self.tone(for: indicator) else { return nil }
        return SettingsSidebarProviderStatus(
            tone: tone,
            text: SettingsSidebarProviderRow.statusDescription(for: indicator))
    }

    /// The tone for a service status. Operational and unknown statuses stay quiet.
    static func tone(for indicator: ProviderStatusIndicator?) -> MacStatusTone? {
        switch indicator ?? .unknown {
        case .none, .unknown: nil
        case .minor: .warning
        case .major, .critical: .error
        case .maintenance: .neutral
        }
    }
}

/// The Settings sidebar: a search field over the panes. The first section lists the app panes; the Providers
/// section has the filter chips and sort menu, one row per provider, and Plugins last. While the field has text,
/// the sidebar lists the matching settings and providers instead.
///
/// The lists are the system sidebar list, so selection, keyboard navigation, drag reordering and context menus stay
/// native; the rows use Internal UI's sidebar metrics and status tones.
@MainActor
struct SettingsSidebarView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @Binding var selection: SettingsPane
    let onSelectAbout: () -> Void
    let onReveal: (SettingsSearchEntry) -> Void
    @State private var query: String
    @State private var chosenResult: String?
    @Environment(\.undoManager) private var undoManager

    /// - Parameters:
    ///   - onSelectAbout: also runs when About is clicked while it is already selected, to leave its subpages.
    ///   - onReveal: opens a chosen search result (`PreferencesSelection.reveal`).
    ///   - query: the search text to start with (snapshots).
    init(
        settings: SettingsStore,
        store: UsageStore,
        selection: Binding<SettingsPane>,
        onSelectAbout: @escaping () -> Void = {},
        onReveal: @escaping (SettingsSearchEntry) -> Void = { _ in },
        query: String = "")
    {
        self.settings = settings
        self.store = store
        self._selection = selection
        self.onSelectAbout = onSelectAbout
        self.onReveal = onReveal
        self._query = State(initialValue: query)
    }

    var body: some View {
        VStack(spacing: MacSpace.chromeGap) {
            MacTextField(L("Search settings"), text: self.$query, systemImage: "magnifyingglass", clearable: true)
                .macControlSize(.large)
                .padding(.horizontal, MacSpace.panelPadding)

            if self.isSearching {
                SettingsSidebarSearchResultsList(
                    results: self.searchResults,
                    chosen: self.$chosenResult,
                    onChoose: self.onReveal,
                    onClear: { self.query = "" })
            } else {
                self.paneList
            }
        }
        .onChange(of: self.query) { _, _ in
            self.chosenResult = nil
        }
    }

    // MARK: Panes

    private var paneList: some View {
        let providers = self.visibleProviders
        return List(selection: self.paneSelection) {
            Section {
                ForEach(self.availableAppPanes, id: \.self) { pane in
                    if pane == .about {
                        SettingsSidebarAboutRow(onSelect: self.onSelectAbout)
                            .tag(pane)
                    } else {
                        SettingsSidebarPaneRow(pane: pane)
                            .tag(pane)
                    }
                }
            }

            Section {
                SettingsSidebarProviderTools(
                    settings: self.settings,
                    filter: self.filter,
                    onRestore: self.restoreProviderOrder)

                ForEach(providers, id: \.self) { provider in
                    SettingsSidebarProviderRow(
                        provider: provider,
                        store: self.store,
                        isEnabled: self.enabledBinding(for: provider))
                        .tag(SettingsPane.provider(provider.instanceID))
                }
                .onMove(perform: self.moveAction(for: providers))

                if providers.isEmpty {
                    MacEmptyState(
                        L("No matching providers"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        size: .compact,
                        secondary: MacEmptyStateAction(L("Clear filters")) {
                            self.settings.providersEnabledOnly = false
                        })
                }

                SettingsSidebarPaneRow(pane: .plugins)
                    .tag(SettingsPane.plugins)
            } header: {
                SettingsSidebarProvidersHeader(enabledCount: self.enabledProviderCount)
            }
        }
        .listStyle(.sidebar)
    }

    private var paneSelection: Binding<SettingsPane?> {
        Binding(
            get: { self.selection },
            set: { newValue in
                guard let newValue else { return }
                self.selection = newValue
            })
    }

    private var availableAppPanes: [SettingsPane] {
        SettingsPane.appPanes.filter { $0 != .debug || self.settings.debugMenuEnabled }
    }

    // MARK: Providers

    private var filter: Binding<SettingsSidebarProviderFilter> {
        Binding(
            get: { SettingsSidebarProviderFilter(enabledOnly: self.settings.providersEnabledOnly) },
            set: { self.settings.providersEnabledOnly = $0.enabledOnly })
    }

    private var orderedProviders: [UsageProvider] {
        guard self.settings.providersSortedAlphabetically else {
            return self.settings.orderedProviders().compactMap(\.firstPartyProvider)
        }
        return CodexBarConfig.alphabeticalProviderOrder(enablement: { provider in
            self.isEnabled(provider)
        })
    }

    private var visibleProviders: [UsageProvider] {
        guard self.settings.providersEnabledOnly else { return self.orderedProviders }
        return self.orderedProviders.filter(self.isEnabled)
    }

    private var enabledProviderCount: Int {
        self.orderedProviders.count(where: self.isEnabled)
    }

    private func isEnabled(_ provider: UsageProvider) -> Bool {
        self.settings.isProviderEnabled(provider: provider, metadata: self.store.metadata(for: provider))
    }

    private func enabledBinding(for provider: UsageProvider) -> Binding<Bool> {
        let meta = self.store.metadata(for: provider)
        return Binding(
            get: { self.settings.isProviderEnabled(provider: provider, metadata: meta) },
            set: { newValue in
                self.settings.setProviderEnabled(provider: provider, metadata: meta, enabled: newValue)
            })
    }

    /// The drag-to-reorder action, or nil (no dragging) while the list is sorted or filtered.
    private func moveAction(for visibleProviders: [UsageProvider]) -> ((IndexSet, Int) -> Void)? {
        guard SettingsSidebarProviderFilter.allowsReordering(
            sortedAlphabetically: self.settings.providersSortedAlphabetically,
            filter: self.filter.wrappedValue)
        else { return nil }
        return { fromOffsets, toOffset in
            if self.settings.moveVisibleProviders(
                visibleProviders.map(\.instanceID), fromOffsets: fromOffsets, toOffset: toOffset)
            {
                self.settings.registerProviderOrderUndo(in: self.undoManager)
            }
        }
    }

    private func restoreProviderOrder() {
        if self.settings.restoreDefaultProviderOrder() { self.settings.registerProviderOrderUndo(in: self.undoManager) }
    }

    // MARK: Search

    private var isSearching: Bool {
        !SettingsSearch.words(in: self.query).isEmpty
    }

    private var searchResults: SettingsSearchResults {
        SettingsSearchResults.results(
            for: self.query,
            entries: SettingsSearchIndex.entries(includingDebug: self.settings.debugMenuEnabled),
            providers: self.orderedProviders.map { provider in
                SettingsSearchEntry.provider(provider, displayName: self.store.metadata(for: provider).displayName)
            })
    }
}

// MARK: - Rows

@MainActor
private struct SettingsSidebarPaneRow: View {
    let pane: SettingsPane

    var body: some View {
        Label(self.pane.title, systemImage: self.pane.systemImage)
            .lineLimit(1)
    }
}

@MainActor
private struct SettingsSidebarAboutRow: View {
    let onSelect: () -> Void

    var body: some View {
        SettingsSidebarPaneRow(pane: .about)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // List selection ignores clicks on the already-selected row; this also returns a pushed subpage to About.
            .simultaneousGesture(TapGesture().onEnded { self.onSelect() })
    }
}

@MainActor
private struct SettingsSidebarProvidersHeader: View {
    let enabledCount: Int

    var body: some View {
        HStack(spacing: MacSpace.unit) {
            Text(L("tab_providers"))
            Spacer(minLength: MacSpace.unit)
            Text(String(format: L("providers_on_count"), self.enabledCount))
                .monospacedDigit()
        }
    }
}

/// The row above the providers: All / Enabled chips, and the sort menu.
@MainActor
private struct SettingsSidebarProviderTools: View {
    @Bindable var settings: SettingsStore
    @Binding var filter: SettingsSidebarProviderFilter
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: MacSpace.chromeGap) {
            MacFilterChips(SettingsSidebarProviderFilter.chips, selection: self.$filter, label: L("tab_providers"))
            Spacer(minLength: 0)
            MacToolMenu(L("Provider sorting"), systemImage: "arrow.up.arrow.down") {
                Toggle(
                    L("Sort providers alphabetically (enabled first)"),
                    isOn: self.$settings.providersSortedAlphabetically)
                Divider()
                Button(L("Restore default order"), action: self.onRestore)
                    .disabled(!self.settings.canRestoreDefaultProviderOrder)
                    .help(L("Also restores the provider order in the menu bar. Can be undone."))
                Button(L("Undo")) {
                    self.settings.undoProviderOrderChange()
                }
                .disabled(!self.settings.canUndoProviderOrderChange)
            }
        }
    }
}

/// A provider's logo at the sidebar symbol size.
@MainActor
private struct SettingsSidebarProviderIcon: View {
    let provider: UsageProvider

    var body: some View {
        Group {
            if let brand = ProviderBrandIcon.image(for: self.provider) {
                Image(nsImage: brand)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "circle.dotted")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: MacSize.sidebarIcon, height: MacSize.sidebarIcon)
        .accessibilityHidden(true)
    }
}

@MainActor
struct SettingsSidebarProviderRow: View {
    /// How far a disabled provider's row fades.
    static let disabledOpacity = 0.55

    let provider: UsageProvider
    @Bindable var store: UsageStore
    @Binding var isEnabled: Bool

    var body: some View {
        let status = self.status
        Label {
            HStack(spacing: MacSpace.unit) {
                Text(self.name)
                    .lineLimit(1)
                Spacer(minLength: MacSpace.unit)
                if let status {
                    SettingsSidebarStatusSymbol(status: status)
                }
            }
        } icon: {
            SettingsSidebarProviderIcon(provider: self.provider)
        }
        .opacity(self.isEnabled ? 1 : Self.disabledOpacity)
        .contextMenu {
            Button(self.isEnabled ? L("Disable") : L("Enable")) {
                self.isEnabled.toggle()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(
            name: self.name,
            isEnabled: self.isEnabled,
            statusChecksEnabled: self.store.statusChecksEnabled,
            indicator: self.store.status(for: self.provider)?.indicator))
        .accessibilityValue(self.fetchStateDescription(status) ?? "")
    }

    private var name: String {
        self.store.metadata(for: self.provider).displayName
    }

    private var status: SettingsSidebarProviderStatus? {
        let hasError = self.store.error(for: self.provider) != nil
        return SettingsSidebarProviderStatus.resolve(
            isEnabled: self.isEnabled,
            isRefreshing: self.store.refreshingProviders.contains(self.provider.instanceID),
            error: hasError ? self.store.userFacingErrorPresentation(for: self.provider)?.message : nil,
            statusChecksEnabled: self.store.statusChecksEnabled,
            indicator: self.store.status(for: self.provider)?.indicator)
    }

    /// Refreshing and refresh errors, which the label (service status) does not cover.
    private func fetchStateDescription(_ status: SettingsSidebarProviderStatus?) -> String? {
        guard let status, status.tone == .busy || self.store.error(for: self.provider) != nil else { return nil }
        return status.text
    }

    nonisolated static func accessibilityLabel(
        name: String,
        isEnabled: Bool,
        statusChecksEnabled: Bool,
        indicator: ProviderStatusIndicator?) -> String
    {
        guard isEnabled else { return "\(name) — \(L("Disabled"))" }
        guard statusChecksEnabled else { return name }
        return "\(name) — \(self.statusDescription(for: indicator))"
    }

    nonisolated static func statusDescription(for indicator: ProviderStatusIndicator?) -> String {
        L("Provider service status: %@", (indicator ?? .unknown).label)
    }
}

/// A status tone as its symbol (a spinner for busy), with the status text as its tooltip.
@MainActor
private struct SettingsSidebarStatusSymbol: View {
    let status: SettingsSidebarProviderStatus

    var body: some View {
        Group {
            if self.status.tone == .busy {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: self.status.tone.systemImage)
                    .font(MacTextRole.caption.font)
                    .foregroundStyle(self.status.tone.color)
            }
        }
        .help(self.status.text)
    }
}

// MARK: - Search results

/// The sidebar while searching: matching settings, each with its pane, then matching providers. Choosing one opens
/// its pane and points the detail at the setting.
@MainActor
private struct SettingsSidebarSearchResultsList: View {
    let results: SettingsSearchResults
    @Binding var chosen: String?
    let onChoose: (SettingsSearchEntry) -> Void
    let onClear: () -> Void

    var body: some View {
        if self.results.isEmpty {
            MacEmptyState(
                L("No matching settings or providers"),
                systemImage: "magnifyingglass",
                size: .compact,
                secondary: MacEmptyStateAction(L("Clear"), action: self.onClear))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: self.choice) {
                if !self.results.settings.isEmpty {
                    Section {
                        ForEach(self.results.settings) { entry in
                            SettingsSidebarSettingResultRow(entry: entry)
                                .tag(entry.id)
                        }
                    }
                }
                if !self.results.providers.isEmpty {
                    Section(L("tab_providers")) {
                        ForEach(self.results.providers) { entry in
                            SettingsSidebarProviderResultRow(entry: entry)
                                .tag(entry.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var choice: Binding<String?> {
        Binding(
            get: { self.chosen },
            set: { id in
                self.chosen = id
                guard let id,
                      let entry = (self.results.settings + self.results.providers).first(where: { $0.id == id })
                else { return }
                self.onChoose(entry)
            })
    }
}

@MainActor
private struct SettingsSidebarSettingResultRow: View {
    let entry: SettingsSearchEntry

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(self.entry.title)
                    .lineLimit(2)
                // A pane's own entry is the pane; a setting names the pane it is on.
                if self.entry.id != self.entry.pane.persistenceToken {
                    Text(self.entry.pane.title)
                        .font(MacTextRole.caption.font)
                        // Hierarchical, so it follows the row's selected text colour.
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: self.entry.pane.systemImage)
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct SettingsSidebarProviderResultRow: View {
    let entry: SettingsSearchEntry

    var body: some View {
        Label {
            Text(self.entry.title)
                .lineLimit(1)
        } icon: {
            if case let .provider(instanceID) = self.entry.pane, let provider = instanceID.firstPartyProvider {
                SettingsSidebarProviderIcon(provider: provider)
            }
        }
    }
}
