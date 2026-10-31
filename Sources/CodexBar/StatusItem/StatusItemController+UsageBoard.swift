import AppKit
import CodexBarCore
import os

extension StatusItemController {
    private static let usageBoardLog = Logger(subsystem: "com.steipete.codexbar", category: "app")

    /// Packaged CodexBar.app always uses the board. Test hosts are not `.app` bundles, so they
    /// keep the classic menu. `TestProcessSafety` alone is too broad to be the production gate.
    static var prefersUsageBoard: Bool {
        if ProcessInfo.processInfo.environment["CODEXBAR_FORCE_CLASSIC_MENU"] == "1" {
            return false
        }
        if Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            return true
        }
        return !SettingsStore.isRunningTests
    }

    func bindPresentedInterface(for item: NSStatusItem, menu: NSMenu?) {
        if Self.prefersUsageBoard {
            let hadMenu = item.menu != nil
            let button = item.button
            let actionWasBound = button?.action == #selector(self.handleUsageBoardStatusClick(_:))
                && button?.target === self
            self.installUsageBoardClick(on: item)
            if item.menu != nil {
                item.menu = nil
            }
            if button != nil, hadMenu || !actionWasBound {
                let identity = item.autosaveName ?? "status-item"
                Self.usageBoardLog.info("usage board: bound status item \(identity, privacy: .public)")
            }
            return
        }
        if item.menu !== menu {
            item.menu = menu
        }
    }

    func reassertVisibleUsageBoardBindings() {
        guard Self.prefersUsageBoard else { return }
        self.bindPresentedInterface(for: self.statusItem, menu: nil)
        for item in self.statusItems.values {
            self.bindPresentedInterface(for: item, menu: nil)
        }
    }

    func redirectOpenRootMenuToUsageBoard(_ menu: NSMenu) -> Bool {
        guard Self.prefersUsageBoard, !self.isPresentingClassicMenu else { return false }
        if self.isRedirectingUsageBoardMenu { return true }
        guard menu.supermenu == nil, self.isUsageBoardRootMenu(menu) else { return false }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.type == .rightMouseUp { return false }
        if event?.modifierFlags.contains(.option) == true { return false }
        let item = self.statusItemOwning(menu) ?? self.statusItem
        self.isRedirectingUsageBoardMenu = true
        // A left click must not be eaten by an attached NSMenu. Cancel that menu and
        // open the board unless this same click already did.
        item.menu = nil
        let alreadyOpened = self.usageBoard?.isVisible == true
            && ProcessInfo.processInfo.systemUptime - self.usageBoardOpenedAt < 0.5
        if !alreadyOpened {
            let identity = item.autosaveName ?? "status-item"
            Self.usageBoardLog.info(
                "usage board: click type=menuWillOpen button=\(identity, privacy: .public)")
        }
        menu.cancelTrackingWithoutAnimation()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRedirectingUsageBoardMenu = false
            self.bindPresentedInterface(for: item, menu: nil)
            if self.usageBoard?.isVisible != true {
                self.toggleUsageBoard(anchoredTo: item, reason: "classic menu redirected")
            }
        }
        return true
    }

    func reloadUsageBoardIfVisible() {
        guard Self.prefersUsageBoard, self.usageBoard?.isVisible == true else { return }
        self.reloadUsageBoardContents()
    }

    @objc func handleUsageBoardStatusClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let typeName = Self.usageBoardEventTypeName(event?.type)
        guard let item = self.statusItem(forStatusButton: sender) else { return }
        let buttonName = item.autosaveName ?? sender.accessibilityIdentifier() ?? "status-button"
        if self.shouldIgnoreDuplicateUsageBoardClick(type: event?.type) {
            Self.usageBoardLog.debug(
                "usage board: click ignored type=\(typeName, privacy: .public) button=\(buttonName, privacy: .public)")
            return
        }
        Self.usageBoardLog.info(
            "usage board: click type=\(typeName, privacy: .public) button=\(buttonName, privacy: .public)")
        let wantsClassicMenu = event?.type == .rightMouseDown
            || event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.option) == true
        if wantsClassicMenu {
            self.usageBoard?.dismiss(reason: "classic menu")
            self.presentClassicMenu(for: item)
        } else {
            // Clear a menu AppKit may have reattached so the next left click is not swallowed.
            if item.menu != nil {
                item.menu = nil
            }
            self.toggleUsageBoard(anchoredTo: item, reason: "status item click")
        }
        self.lastUsageBoardClickTypeRaw = event?.type.rawValue
        self.usageBoardClickUptime = ProcessInfo.processInfo.systemUptime
    }

    func toggleUsageBoard(anchoredTo item: NSStatusItem, reason: String) {
        if self.usageBoard?.isVisible == true, self.usageBoard?.anchoredStatusItem() === item {
            let age = ProcessInfo.processInfo.systemUptime - self.usageBoardOpenedAt
            if age < 0.5 {
                let ageText = String(format: "%.2f", age)
                Self.usageBoardLog.debug(
                    "usage board: ignoring close, opened \(ageText, privacy: .public)s ago")
                return
            }
            self.usageBoard?.dismiss(reason: reason)
            return
        }
        let board = self.ensureUsageBoard()
        let selection = self.preferredBoardSelection(for: item)
        if board.session.providers.isEmpty {
            board.session.isShowingSkeleton = true
        }
        board.present(anchoredTo: item, reason: reason)
        self.usageBoardOpenedAt = ProcessInfo.processInfo.systemUptime
        // Provider cards and menu actions are built after the panel is on screen.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reloadUsageBoardContents(selecting: selection)
            self.store.noteMenuOpened()
        }
    }

    func presentClassicMenu(for item: NSStatusItem) {
        guard let menu = self.classicMenu(for: item), let button = item.button else { return }
        self.isPresentingClassicMenu = true
        defer { self.isPresentingClassicMenu = false }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
}

extension StatusItemController {
    private func installUsageBoardClick(on item: NSStatusItem) {
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(self.handleUsageBoardStatusClick(_:))
        // One edge per button. Down and up together toggled the board open and closed
        // in a single click once building the panel took longer than the debounce.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func shouldIgnoreDuplicateUsageBoardClick(type: NSEvent.EventType?) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - self.usageBoardClickUptime < 0.5,
              let type, let lastRaw = self.lastUsageBoardClickTypeRaw else { return false }
        let last = NSEvent.EventType(rawValue: lastRaw)
        if type == last { return true }
        switch (last, type) {
        case (.leftMouseDown, .leftMouseUp), (.leftMouseUp, .leftMouseDown),
             (.rightMouseDown, .rightMouseUp), (.rightMouseUp, .rightMouseDown):
            return true
        default:
            return false
        }
    }

    private static func usageBoardEventTypeName(_ type: NSEvent.EventType?) -> String {
        switch type {
        case .leftMouseDown: "leftMouseDown"
        case .leftMouseUp: "leftMouseUp"
        case .rightMouseDown: "rightMouseDown"
        case .rightMouseUp: "rightMouseUp"
        case .none: "none"
        default: "other"
        }
    }

    private func isUsageBoardRootMenu(_ menu: NSMenu) -> Bool {
        if menu === self.mergedMenu || menu === self.fallbackMenu { return true }
        return self.providerMenus.values.contains { $0 === menu }
    }

    private func statusItemOwning(_ menu: NSMenu) -> NSStatusItem? {
        if menu === self.mergedMenu { return self.statusItem }
        for (instanceID, providerMenu) in self.providerMenus where providerMenu === menu {
            return self.statusItems[instanceID]
        }
        if menu === self.fallbackMenu {
            return self.statusItems.values.first ?? self.statusItem
        }
        return nil
    }

    private func ensureUsageBoard() -> UsageBoardPanelController {
        if let usageBoard = self.usageBoard {
            return usageBoard
        }
        let session = UsageBoardSession()
        session.icon = { [weak self] providerID in
            self?.usageBoardIcon(for: providerID)
        }
        session.onCommand = { [weak self] action in
            self?.performUsageBoardCommand(action)
        }
        session.onSelectionChange = { [weak self] _ in
            self?.refreshUsageBoardCommands()
        }
        let board = UsageBoardPanelController(session: session)
        self.usageBoard = board
        return board
    }

    private func reloadUsageBoardContents() {
        guard let board = self.usageBoard else { return }
        board.session.replaceProviders(
            self.makeUsageBoardProviders(),
            isRefreshing: self.store.isRefreshing || !self.store.refreshingProviders.isEmpty)
        self.refreshUsageBoardCommands()
    }

    private func reloadUsageBoardContents(selecting selectionID: String?) {
        self.usageBoard?.session.select(selectionID)
        self.reloadUsageBoardContents()
    }

    private func preferredBoardSelection(for item: NSStatusItem) -> String? {
        if item === self.statusItem {
            return self.usageBoard?.session.selectionID
        }
        for (instanceID, status) in self.statusItems where status === item {
            return instanceID.rawValue
        }
        return self.usageBoard?.session.selectionID
    }

    private func statusItem(forStatusButton button: NSStatusBarButton) -> NSStatusItem? {
        if self.statusItem.button === button {
            return self.statusItem
        }
        return self.statusItems.values.first { $0.button === button }
    }

    private func classicMenu(for item: NSStatusItem) -> NSMenu? {
        if item === self.statusItem {
            if self.mergedMenu == nil {
                self.mergedMenu = self.makeMenu()
            }
            return self.mergedMenu
        }
        for (instanceID, status) in self.statusItems where status === item {
            if self.providerMenus[instanceID] == nil, let provider = instanceID.firstPartyProvider {
                self.providerMenus[instanceID] = self.makeMenu(for: provider)
            }
            return self.providerMenus[instanceID] ?? self.fallbackMenu
        }
        return self.mergedMenu ?? self.fallbackMenu
    }

    private func makeUsageBoardProviders() -> [UsageBoardProvider] {
        var providers = self.store.enabledFirstPartyProvidersForDisplay().map { provider in
            UsageBoardCardProjection.provider(from: self.store.menuCardModel(for: provider))
        }
        #if canImport(JavaScriptCore)
        providers.append(contentsOf: self.topLevelUserProviderPlugins().map(self.usageBoardProvider(for:)))
        #endif
        return providers
    }

    private func refreshUsageBoardCommands() {
        guard let board = self.usageBoard else { return }
        let providerID = board.session.selectionID
        board.session.providerCommands = self.usageBoardCommands(for: providerID)
        if let providerID, let instanceID = ProviderInstanceID(rawValue: providerID) {
            self.lastMenuProvider = instanceID
        }
    }

    private func usageBoardCommands(for providerID: String?) -> [UsageBoardCommand] {
        guard let providerID else { return [] }
        var commands = [
            UsageBoardCommand(
                id: "refresh-\(providerID)",
                title: L("Refresh"),
                systemImage: "arrow.clockwise",
                action: .refreshProvider(providerID)),
        ]
        if let provider = UsageProvider(rawValue: providerID) {
            let descriptor = self.makeMenuDescriptor(provider: provider, includeContextualActions: true)
            for section in descriptor.sections {
                for entry in section.entries {
                    guard case let .action(title, action) = entry, self.belongsOnUsageBoard(action) else { continue }
                    commands.append(UsageBoardCommand(
                        id: "\(providerID)-\(commands.count)",
                        title: title,
                        systemImage: self.usageBoardSymbol(for: action),
                        action: .menu(action)))
                }
            }
        }
        self.appendCopyErrorCommandIfNeeded(providerID: providerID, commands: &commands)
        return commands
    }

    private func belongsOnUsageBoard(_ action: MenuDescriptor.MenuAction) -> Bool {
        switch action {
        case .switchAccount, .addProviderAccount, .addCodexAccount, .loginToProvider,
             .openTerminal, .dashboard, .statusPage, .changelog, .copyError,
             .providerSettings, .openCodexWorkspaces, .openOpenAILiveUsage,
             .refreshAugmentSession, .requestCodexSystemPromotion:
            true
        default:
            false
        }
    }

    private func usageBoardSymbol(for action: MenuDescriptor.MenuAction) -> String {
        switch action {
        case .loginToProvider, .switchAccount, .addProviderAccount, .addCodexAccount:
            "arrow.right.square"
        case .dashboard, .openOpenAILiveUsage:
            "chart.xyaxis.line"
        case .statusPage:
            "waveform.path.ecg"
        case .copyError:
            "doc.on.doc"
        case .providerSettings:
            "gearshape"
        case .openTerminal:
            "terminal"
        case .openCodexWorkspaces:
            "folder"
        default:
            "arrow.right"
        }
    }

    private func appendCopyErrorCommandIfNeeded(providerID: String, commands: inout [UsageBoardCommand]) {
        guard let provider = self.usageBoard?.session.providers.first(where: { $0.id == providerID }),
              provider.attention == .error || provider.attention == .needsSignIn,
              !provider.subtitle.isEmpty else { return }
        let alreadyCopies = commands.contains { command in
            guard case let .menu(action) = command.action else { return false }
            if case .copyError = action { return true }
            return false
        }
        guard !alreadyCopies else { return }
        commands.append(UsageBoardCommand(
            id: "copy-\(providerID)",
            title: L("Copy error"),
            systemImage: "doc.on.doc",
            action: .menu(.copyError(provider.subtitle))))
    }

    private func performUsageBoardCommand(_ action: UsageBoardCommand.Action) {
        switch action {
        case .close:
            self.usageBoard?.dismiss(reason: "close command")
        case .classicMenu:
            let item = self.usageBoard?.anchoredStatusItem() ?? self.statusItem
            self.usageBoard?.dismiss(reason: "classic menu")
            self.presentClassicMenu(for: item)
        case .refresh:
            self.refreshNow()
        case let .refreshProvider(providerID):
            self.refreshUsageBoardProvider(providerID)
        case .settings:
            self.usageBoard?.dismiss(reason: "settings")
            self.showSettingsGeneral()
        case .quit:
            self.usageBoard?.dismiss(reason: "quit")
            self.quit()
        case let .menu(menuAction):
            self.performUsageBoardMenuAction(menuAction)
        }
    }

    private func refreshUsageBoardProvider(_ providerID: String) {
        guard let instanceID = ProviderInstanceID(rawValue: providerID) else { return }
        if instanceID.firstPartyProvider != nil {
            self.startManualRefresh(
                for: instanceID,
                originatingMenuID: nil,
                originatingMenuInteractionGeneration: nil)
            return
        }
        #if canImport(JavaScriptCore)
        Task { @MainActor in
            await self.store.refreshUserPlugin(instanceID)
        }
        #endif
    }

    private func performUsageBoardMenuAction(_ action: MenuDescriptor.MenuAction) {
        if let providerID = self.usageBoard?.session.selectionID,
           let instanceID = ProviderInstanceID(rawValue: providerID)
        {
            self.lastMenuProvider = instanceID
        }
        switch action {
        case .copyError, .refresh, .refreshAugmentSession:
            break
        default:
            self.usageBoard?.dismiss(reason: "menu action")
        }
        switch action {
        case .dashboard:
            self.openDashboard()
        case .statusPage:
            self.openStatusPage()
        case .changelog:
            self.openChangelog()
        case .refreshAugmentSession:
            self.refreshAugmentSession()
        case let .providerSettings(provider):
            let item = NSMenuItem()
            item.representedObject = provider.rawValue
            self.showProviderSettings(item)
        default:
            let (selector, represented) = self.selector(for: action)
            let item = NSMenuItem()
            item.representedObject = represented
            item.target = self
            _ = self.perform(selector, with: item)
        }
    }

    private func usageBoardIcon(for providerID: String) -> NSImage? {
        if let provider = UsageProvider(rawValue: providerID) {
            return self.brandIcon(provider)
        }
        #if canImport(JavaScriptCore)
        if let instanceID = ProviderInstanceID(rawValue: providerID),
           let plugin = UserProviderPluginRegistry.plugin(for: instanceID)
        {
            return Self.userPluginSVGImage(plugin)
        }
        #endif
        return nil
    }
}

#if canImport(JavaScriptCore)
extension StatusItemController {
    fileprivate func usageBoardProvider(for plugin: UserProviderPlugin) -> UsageBoardProvider {
        let instanceID = plugin.manifest.id
        let snapshot = self.store.snapshot(for: instanceID)
        let error = self.store.errors[instanceID]
        let showUsed = self.settings.usageBarsShowUsed
        var metrics: [UsageBoardMetric] = []
        var lines: [UsageBoardDetailLine] = []
        if let snapshot {
            self.appendUsageBoardWindow(
                snapshot.primary,
                id: "\(instanceID.rawValue)-primary",
                fallbackTitle: L("Primary"),
                showUsed: showUsed,
                metrics: &metrics)
            self.appendUsageBoardWindow(
                snapshot.secondary,
                id: "\(instanceID.rawValue)-secondary",
                fallbackTitle: L("Secondary"),
                showUsed: showUsed,
                metrics: &metrics)
            self.appendUsageBoardWindow(
                snapshot.tertiary,
                id: "\(instanceID.rawValue)-tertiary",
                fallbackTitle: L("Tertiary"),
                showUsed: showUsed,
                metrics: &metrics)
            for named in snapshot.extraRateWindows ?? [] where named.usageKnown {
                self.appendUsageBoardWindow(
                    named.window,
                    id: "\(instanceID.rawValue)-\(named.id)",
                    fallbackTitle: named.title,
                    showUsed: showUsed,
                    metrics: &metrics)
            }
            if let cost = snapshot.providerCost {
                lines.append(UsageBoardDetailLine(
                    id: "\(instanceID.rawValue)-cost",
                    label: cost.period ?? L("Credits"),
                    value: UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode)))
            }
            UsageBoardCardProjection.appendDetails(snapshot.details, metrics: &metrics, lines: &lines)
        }
        let subtitle = error ?? (snapshot == nil ? L("No usage fetched yet") : "")
        let email = snapshot?.identity(for: instanceID)?.accountEmail ?? ""
        return UsageBoardProviderBuilder.make(
            id: instanceID.rawValue,
            name: plugin.manifest.name,
            planText: snapshot?.identity(for: instanceID)?.loginMethod,
            email: email,
            subtitle: subtitle,
            isLoading: snapshot == nil && error == nil && self.store.refreshingProviders.contains(instanceID),
            isError: error != nil,
            metrics: metrics,
            lines: lines,
            notes: [])
    }

    fileprivate func appendUsageBoardWindow(
        _ window: RateWindow?,
        id: String,
        fallbackTitle: String,
        showUsed: Bool,
        metrics: inout [UsageBoardMetric])
    {
        guard let window, !window.isSyntheticPlaceholder else { return }
        let used = min(100, max(0, window.usedPercent))
        let remaining = min(100, max(0, 100 - used))
        let percent = showUsed ? used : remaining
        let suffix = showUsed ? L("usage_percent_suffix_used") : L("usage_percent_suffix_left")
        metrics.append(UsageBoardMetric(
            id: id,
            title: window.title ?? fallbackTitle,
            percent: percent,
            percentText: UsageFormatter.percentText(percent, suffix: suffix),
            resetText: UsageFormatter.resetLine(for: window, style: self.settings.resetTimeDisplayStyle),
            detailText: nil,
            showsBar: true))
    }
}
#endif
