import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

/// Sidebar destinations of the settings window: fixed app panes plus one entry per provider.
///
/// The sidebar lists the app panes in `appPanes` order, then the Providers section: one row per provider
/// followed by Plugins. `SettingsPaneRouter` maps each case to its pane view.
enum SettingsPane: Hashable {
    case general
    case menuBar
    case menu
    case alerts
    case costs
    case sync
    case integrations
    case privacy
    case about
    case debug
    case plugins
    case provider(ProviderInstanceID)

    /// App panes in sidebar order. Debug is listed last and shown only while the debug-settings switch is on.
    static let appPanes: [SettingsPane] = [
        .general,
        .menuBar,
        .menu,
        .alerts,
        .costs,
        .sync,
        .integrations,
        .privacy,
        .about,
        .debug,
    ]

    /// Every pane that is not a provider: the app panes, then Plugins (the last row of the Providers section).
    static let fixedPanes: [SettingsPane] = appPanes + [.plugins]

    var title: String {
        switch self {
        case .general: L("tab_general")
        case .menuBar: L("tab_menu_bar")
        case .menu: L("tab_menu")
        case .alerts: L("tab_alerts")
        case .costs: L("tab_costs")
        case .sync: L("tab_sync")
        case .integrations: L("tab_integrations")
        case .privacy: L("tab_privacy")
        case .about: L("tab_about")
        case .debug: L("tab_debug")
        case .plugins: L("Plugins")
        case let .provider(instanceID):
            instanceID.firstPartyProvider
                .map { ProviderDescriptorRegistry.descriptor(for: $0).metadata.displayName }
                ?? instanceID.rawValue
        }
    }

    /// SF Symbol for the pane's sidebar row. Provider rows draw the provider's brand icon instead.
    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .menuBar: "menubar.rectangle"
        case .menu: "filemenu.and.selection"
        case .alerts: "bell.badge.fill"
        case .costs: "chart.bar.fill"
        case .sync: "icloud.fill"
        case .integrations: "point.3.filled.connected.trianglepath.dotted"
        case .privacy: "hand.raised.fill"
        case .about: "info.circle.fill"
        case .debug: "ladybug.fill"
        case .plugins: "puzzlepiece.extension.fill"
        case .provider: "circle.dotted"
        }
    }
}

@MainActor
struct PreferencesView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @Bindable var cloudSyncState: CloudSyncState
    let updater: UpdaterProviding
    @Bindable var selection: PreferencesSelection
    let managedCodexAccountCoordinator: ManagedCodexAccountCoordinator
    let codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator
    let runProviderLoginFlow: @MainActor (UsageProvider) async -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingsPane.sidebarWidthDefaultsKey) private var sidebarWidth: Double = SettingsPane.sidebarWidth

    init(
        settings: SettingsStore,
        store: UsageStore,
        cloudSyncState: CloudSyncState = CloudSyncState(),
        updater: UpdaterProviding,
        selection: PreferencesSelection,
        managedCodexAccountCoordinator: ManagedCodexAccountCoordinator = ManagedCodexAccountCoordinator(),
        codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator? = nil,
        runProviderLoginFlow: @escaping @MainActor (UsageProvider) async -> Void = { _ in })
    {
        self.settings = settings
        self.store = store
        self.cloudSyncState = cloudSyncState
        self.updater = updater
        self.selection = selection
        self.managedCodexAccountCoordinator = managedCodexAccountCoordinator
        self.codexAccountPromotionCoordinator = codexAccountPromotionCoordinator
            ?? CodexAccountPromotionCoordinator(
                settingsStore: settings,
                usageStore: store,
                managedAccountCoordinator: managedCodexAccountCoordinator)
        self.runProviderLoginFlow = runProviderLoginFlow
    }

    var body: some View {
        SettingsWindowLayout(selection: self.selection, sidebarWidth: self.$sidebarWidth) {
            SettingsSidebarView(
                settings: self.settings,
                store: self.store,
                selection: self.$selection.pane,
                onSelectAbout: { self.selection.requestAboutRoot() },
                onReveal: { self.selection.reveal($0) })
        } detail: {
            SettingsPaneRouter(pane: self.selection.pane, context: self.paneContext)
        }
        .frame(
            minWidth: SettingsPane.windowMinWidth,
            idealWidth: SettingsPane.windowWidth,
            maxWidth: .infinity,
            minHeight: SettingsPane.windowMinHeight,
            idealHeight: SettingsPane.windowHeight,
            maxHeight: .infinity)
        .id(self.settings.appLanguage)
        .codexBarLocalized()
        .background {
            SettingsWindowAppearanceBridge(colorScheme: self.colorScheme)
                .allowsHitTesting(false)
        }
        .onAppear {
            self.ensureValidSelection()
        }
        .onChange(of: self.settings.debugMenuEnabled) { _, _ in
            self.ensureValidSelection()
        }
        .onChange(of: self.settings.shouldRequestAdaptiveActivityScanConsent) { _, shouldRequest in
            guard shouldRequest else { return }
            AdaptiveActivityConsentPresenter.presentIfNeeded(settings: self.settings)
        }
    }

    private var paneContext: SettingsPaneContext {
        SettingsPaneContext(
            settings: self.settings,
            store: self.store,
            cloudSyncState: self.cloudSyncState,
            updater: self.updater,
            selection: self.selection,
            managedCodexAccountCoordinator: self.managedCodexAccountCoordinator,
            codexAccountPromotionCoordinator: self.codexAccountPromotionCoordinator,
            runProviderLoginFlow: self.runProviderLoginFlow)
    }

    private func ensureValidSelection() {
        guard !self.settings.debugMenuEnabled else { return }
        if self.selection.pane == .debug {
            self.selection.pane = .general
        }
        self.selection.removeFromHistory { $0 == .debug }
    }
}

/// The Settings window's one layout, on macOS 15 and 26: the system split view, so the sidebar, its divider and the
/// toolbar come from the system (Liquid Glass on 26). The detail shows the selected pane, which draws its own title
/// row; the window title follows the pane for the Window menu and VoiceOver, and the toolbar leaves it out.
/// `PreferencesView` fills it with the sidebar and the routed pane; snapshot tests use a placeholder pane.
@MainActor
struct SettingsWindowLayout<Sidebar: View, Detail: View>: View {
    @Bindable var selection: PreferencesSelection
    @Binding var sidebarWidth: Double
    let sidebar: Sidebar
    let detail: Detail
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(
        selection: PreferencesSelection,
        sidebarWidth: Binding<Double>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail)
    {
        self.selection = selection
        self._sidebarWidth = sidebarWidth
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        NavigationSplitView(columnVisibility: self.$columnVisibility) {
            self.sidebar
                .modifier(SettingsSidebarSizing(width: self.$sidebarWidth))
        } detail: {
            self.detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(IUColor.window)
                .navigationTitle(self.selection.title)
                .toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        SettingsHistoryButtons(selection: self.selection)
                    }
                }
        }
    }
}

@MainActor
enum SettingsWindowSizing {
    static func enforceMinimumSize(_ window: NSWindow) {
        let toolbarHeight = max(0, window.frame.height - window.contentLayoutRect.height)
        let minimumSize = NSSize(
            width: SettingsPane.windowMinWidth,
            height: SettingsPane.windowMinHeight + toolbarHeight)
        window.minSize = minimumSize

        if window.frame.width < minimumSize.width || window.frame.height < minimumSize.height {
            var frame = window.frame
            let repairedSize = NSSize(
                width: max(frame.width, minimumSize.width),
                height: max(frame.height, minimumSize.height))
            frame.origin.y += frame.height - repairedSize.height
            frame.size = repairedSize
            window.setFrame(frame, display: true)
        }
    }
}

@MainActor
enum SettingsWindowStageBehavior {
    /// Keep Settings on the current Stage Manager stage / Space instead of
    /// yanking focus back to wherever the window last appeared.
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .moveToActiveSpace,
        .fullScreenAuxiliary,
    ]

    static func applyCollectionBehavior(_ window: NSWindow) {
        // Assign the exact OptionSet. `.canJoinAllSpaces` is mutually exclusive
        // with `.moveToActiveSpace`, and SwiftUI may restore a stale Space mask.
        if window.collectionBehavior != self.collectionBehavior {
            window.collectionBehavior = self.collectionBehavior
        }
    }

    static func present(_ window: NSWindow) {
        self.applyCollectionBehavior(window)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
enum SettingsWindowAppearance {
    typealias ResetAction = @MainActor @Sendable () -> Void
    typealias ResetScheduler = @MainActor @Sendable (@escaping ResetAction) -> Void

    static func refresh(
        _ window: NSWindow,
        application: NSApplication = NSApp,
        scheduleReset: ResetScheduler = Self.scheduleReset)
    {
        SettingsWindowSizing.enforceMinimumSize(window)
        window.appearanceSource = application
        // Pulse the exact effective appearance so the native toolbar redraws without
        // dropping inherited accessibility attributes, then restore KVO inheritance.
        window.appearance = application.effectiveAppearance
        scheduleReset { [weak window] in
            if let window {
                SettingsWindowSizing.enforceMinimumSize(window)
            }
            window?.appearance = nil
            window?.viewsNeedDisplay = true
        }
    }

    static func scheduleReset(_ action: @escaping ResetAction) {
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}

@MainActor
struct SettingsWindowAppearanceBridge: NSViewRepresentable {
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> SettingsWindowAppearanceView {
        SettingsWindowAppearanceView()
    }

    func updateNSView(_ nsView: SettingsWindowAppearanceView, context: Context) {
        nsView.refreshWindowAppearance(for: self.colorScheme)
    }
}

@MainActor
final class SettingsWindowAppearanceView: NSView {
    private let scheduleReset: SettingsWindowAppearance.ResetScheduler
    private var colorScheme: ColorScheme?

    init(scheduleReset: @escaping SettingsWindowAppearance.ResetScheduler = SettingsWindowAppearance.scheduleReset) {
        self.scheduleReset = scheduleReset
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didUpdateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.windowDidUpdate(_:)),
                name: NSWindow.didUpdateNotification,
                object: window)
        }
        self.configureWindowStyle()
        if let window {
            SettingsWindowAppearance.refresh(window, scheduleReset: self.scheduleReset)
        }
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        self.configureWindowStyle()
    }

    func refreshWindowAppearance(for colorScheme: ColorScheme) {
        guard self.colorScheme != colorScheme else { return }
        self.colorScheme = colorScheme
        guard let window else { return }
        self.configureWindowStyle()
        SettingsWindowAppearance.refresh(window, scheduleReset: self.scheduleReset)
    }

    override func layout() {
        super.layout()
        self.configureWindowStyle()
    }

    private func configureWindowStyle() {
        guard let window else { return }
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        if !window.styleMask.contains(.miniaturizable) {
            window.styleMask.insert(.miniaturizable)
        }
        // Full-size content lets the sidebar run up under the toolbar, as in a SwiftUI window; content stays
        // below the toolbar through the safe area.
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}

@MainActor
struct SettingsHistoryButtons: View {
    @Bindable var selection: PreferencesSelection

    var body: some View {
        ControlGroup {
            Button {
                self.selection.goBack()
            } label: {
                Label(L("Back"), systemImage: "chevron.backward")
            }
            .disabled(!self.selection.canGoBack)
            .keyboardShortcut("[", modifiers: .command)
            .help(L("Back"))

            Button {
                self.selection.goForward()
            } label: {
                Label(L("Forward"), systemImage: "chevron.forward")
            }
            .disabled(!self.selection.canGoForward)
            .keyboardShortcut("]", modifiers: .command)
            .help(L("Forward"))
        }
        .controlGroupStyle(.navigation)
        .labelStyle(.iconOnly)
        .fixedSize()
    }
}
