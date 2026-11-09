import AppKit
import CodexBarCore
import Observation
import SwiftUI

@MainActor
enum ProviderSettingsRefreshInteraction {
    static func perform<Result>(operation: () async -> Result) async -> Result {
        await BrowserCookieAccessGate.withExplicitRetry {
            await ProviderInteractionContext.$current.withValue(.userInitiated) {
                await operation()
            }
        }
    }
}

/// The provider list's search rule, shared by the Settings sidebar.
enum ProvidersPane {
    static func filteredProviders(
        _ providers: [UsageProvider],
        query: String,
        displayName: (UsageProvider) -> String) -> [UsageProvider]
    {
        let words = SettingsSearch.words(in: query)
        guard !words.isEmpty else { return providers }
        return providers.filter { provider in
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            let fields = [
                displayName(provider),
                descriptor.metadata.shortDisplayName,
                provider.rawValue,
                descriptor.cli.name,
            ] + descriptor.cli.aliases
            return SettingsSearch.matches(words: words, fields: fields)
        }
    }
}

/// Everything one provider's Settings page reads and does: the descriptors its sections render, the Codex account
/// actions, the confirmation it is asking for, and the transient status text provider toggles report.
/// `ProviderSettingsPane` owns one per provider page; tests build one directly.
@MainActor
@Observable
final class ProviderSettingsPageModel {
    let provider: UsageProvider
    let settings: SettingsStore
    let store: UsageStore
    @ObservationIgnored let managedCodexAccountCoordinator: ManagedCodexAccountCoordinator
    @ObservationIgnored let codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator
    @ObservationIgnored let codexAmbientLoginRunner: any CodexAmbientLoginRunning
    @ObservationIgnored let runProviderLoginFlow: @MainActor (UsageProvider) async -> Void

    var isErrorExpanded = false
    var activeConfirmation: ProviderSettingsConfirmationState?
    private(set) var codexAccountsNotice: CodexAccountsSectionNotice?
    private(set) var isAuthenticatingLiveCodexAccount = false
    private var settingsStatusTextByID: [String: String] = [:]
    private var settingsLastAppActiveRunAtByID: [String: Date] = [:]

    init(
        // Provider-specific by design: Codex is the historical settings selection when no provider is supplied.
        provider: UsageProvider = .codex,
        settings: SettingsStore,
        store: UsageStore,
        managedCodexAccountCoordinator: ManagedCodexAccountCoordinator = ManagedCodexAccountCoordinator(),
        codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator? = nil,
        codexAmbientLoginRunner: any CodexAmbientLoginRunning = DefaultCodexAmbientLoginRunner(),
        runProviderLoginFlow: @escaping @MainActor (UsageProvider) async -> Void = { _ in })
    {
        self.provider = provider
        self.settings = settings
        self.store = store
        self.managedCodexAccountCoordinator = managedCodexAccountCoordinator
        self.codexAccountPromotionCoordinator = codexAccountPromotionCoordinator
            ?? CodexAccountPromotionCoordinator(
                settingsStore: settings,
                usageStore: store,
                managedAccountCoordinator: managedCodexAccountCoordinator)
        self.codexAmbientLoginRunner = codexAmbientLoginRunner
        self.runProviderLoginFlow = runProviderLoginFlow
    }

    // MARK: - Page content

    /// What the page shows right now, read fresh on every render.
    func pageContent() -> ProviderSettingsPageContent {
        let provider = self.provider
        let unfilteredModel = UsageMenuCardView.Model.make(self.store.menuCardInput(
            for: provider, context: .settings))
        // Provider-specific by design: only Codex has managed OAuth account snapshots for this shared settings view.
        let overview = provider == .codex ? self.store.codexAccountUsageOverview { accountIDs in
            Task { @MainActor in
                await ProviderSettingsRefreshInteraction.perform {
                    await self.store.refreshCodexAccountsForSettings(accountIDs)
                }
            }
        } : nil
        let visibilityModel = UsageMenuCardView.Model.make(self.store.menuCardInput(
            for: provider, context: .settings, optionalUsageOverride: true))
        let hiddenItemIDs = self.settings.hiddenUsageItemIDs(for: provider)
        let usageItems = ((overview?.usageItems ?? []) + visibilityModel.usageItemDescriptors(
            includingHidden: hiddenItemIDs,
            hidePersonalInfo: self.settings.hidePersonalInfo))
            .reduce(into: [ProviderUsageItemDescriptor]()) { items, item in
                if !items.contains(where: { $0.id == item.id }) { items.append(item) }
            }
        let model = unfilteredModel.applyingUsageItemVisibility(hiddenItemIDs: hiddenItemIDs)
        let tokenAccounts = self.tokenAccountDescriptor(for: provider).flatMap { descriptor in
            (descriptor.isVisible?() ?? true) ? descriptor : nil
        }
        return ProviderSettingsPageContent(
            provider: provider,
            displayName: self.store.metadata(for: provider).displayName,
            subtitle: overview.map { L("%@ accounts", String($0.rows.count)) } ?? self.providerSubtitle(provider),
            model: model,
            accountUsageOverview: overview,
            usageItems: usageItems,
            statusFacts: ProviderStatusFacts.rows(
                provider: provider,
                store: self.store,
                model: model,
                showsAccountInfo: overview == nil),
            errorDisplay: overview == nil ? self.providerErrorDisplay(provider) : nil,
            openAIWebDiagnostic: self.openAIWebDiagnostic(for: provider),
            pickers: self.extraSettingsPickers(for: provider),
            toggles: self.extraSettingsToggles(for: provider),
            fields: self.extraSettingsFields(for: provider),
            directoryLists: self.extraSettingsDirectoryLists(for: provider),
            modelLimits: self.extraSettingsModelLimits(for: provider),
            actions: self.extraSettingsActions(for: provider),
            tokenAccounts: tokenAccounts,
            organizations: self.extraSettingsOrganizations(for: provider),
            codexAccounts: self.codexAccountsSectionState(for: provider),
            showsMenuBarMetric: ProviderMenuBarPercentWindowSettingsView(
                provider: provider,
                settings: self.settings,
                snapshot: self.store.snapshot(for: provider.instanceID)).isVisible)
    }

    var isRefreshing: Bool {
        self.store.refreshingProviders.contains(self.provider.instanceID)
    }

    // MARK: - Enabled, subtitle, refresh

    func refresh() {
        let provider = self.provider
        Task { @MainActor in
            await ProviderSettingsRefreshInteraction.perform {
                // Provider-specific by design: Codex account reconciliation must refresh managed profile state too.
                if provider == .codex {
                    await self.store.refreshCodexAccountScopedState(allowDisabled: true)
                } else {
                    await self.store.refreshProvider(provider, allowDisabled: true)
                }
            }
        }
    }

    func binding(for provider: UsageProvider) -> Binding<Bool> {
        let meta = self.store.metadata(for: provider)
        return Binding(
            get: { self.settings.isProviderEnabled(provider: provider, metadata: meta) },
            set: { newValue in
                self.settings.setProviderEnabled(provider: provider, metadata: meta, enabled: newValue)
            })
    }

    private func providerUsageText(_ provider: UsageProvider) -> String {
        if self.store.isStale(provider: provider) { return L("last_fetch_failed") }
        let snapshot = self.store.presentationSnapshot(for: provider)
        // Successful refreshes clear remembered availability; resolve quota-less successes from the snapshot.
        let availability = self.store.knownLimitsAvailability(for: provider)
            ?? UsageLimitsAvailability.resolve(provider: provider, snapshot: snapshot)
        if availability.isUnavailable { return L("Limits not available") }
        return snapshot?.updatedAt.relativeDescription() ?? L("usage_not_fetched_yet")
    }

    func providerSubtitle(_ provider: UsageProvider) -> String {
        let meta = self.store.metadata(for: provider)
        let presentationContext = ProviderPresentationContext(
            provider: provider,
            settings: self.settings,
            store: self.store,
            metadata: meta)
        let presentation = ProviderCatalog.implementation(for: provider)?
            .presentation(context: presentationContext)
            ?? ProviderPresentation(detailLine: ProviderPresentation.standardDetailLine)
        let detailLine = presentation.detailLine(presentationContext)

        return "\(detailLine)\n\(self.providerUsageText(provider))"
    }

    func providerSidebarSubtitle(_ provider: UsageProvider) -> String {
        let meta = self.store.metadata(for: provider)
        let detailLine: String = if let sourceLabel = self.store.lastSourceLabels[provider.instanceID],
                                    !sourceLabel.isEmpty
        {
            sourceLabel
        } else if let version = self.store.version(for: provider), !version.isEmpty {
            "\(meta.cliName) \(version)"
        } else {
            meta.cliName
        }

        return "\(detailLine)\n\(self.providerUsageText(provider))"
    }

    // MARK: - Error

    func providerErrorDisplay(_ provider: UsageProvider) -> ProviderErrorDisplay? {
        guard let full = self.store.error(for: provider) ?? self.store.diagnostic(for: provider),
              !full.isEmpty
        else { return nil }
        let preview = self.store.userFacingError(for: provider) ?? full
        return ProviderErrorDisplay(
            title: String(
                format: L("last_fetch_failed_with_provider"),
                self.store.metadata(for: provider).displayName),
            preview: Self.truncated(preview),
            full: full)
    }

    func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func truncated(_ text: String, maxLength: Int = 160) -> String {
        var message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.count > maxLength {
            let idx = message.index(message.startIndex, offsetBy: maxLength)
            message = "\(message[..<idx])…"
        }
        return message
    }

    // MARK: - Provider descriptors

    private func extraSettingsToggles(for provider: UsageProvider) -> [ProviderSettingsToggleDescriptor] {
        guard let impl = ProviderCatalog.implementation(for: provider) else { return [] }
        let context = self.makeSettingsContext(provider: provider)
        return impl.settingsToggles(context: context)
            .filter { $0.isVisible?() ?? true }
    }

    func extraSettingsPickers(for provider: UsageProvider) -> [ProviderSettingsPickerDescriptor] {
        guard let impl = ProviderCatalog.implementation(for: provider) else { return [] }
        let context = self.makeSettingsContext(provider: provider)
        // The token layout editor is the only text-style menu bar UI. Legacy metric keys remain persisted solely for
        // migration and downgrade safety, so provider settings no longer append their former menu bar metric picker.
        return impl.settingsPickers(context: context)
            .filter { $0.isVisible?() ?? true }
    }

    private func extraSettingsFields(for provider: UsageProvider) -> [ProviderSettingsFieldDescriptor] {
        guard let impl = ProviderCatalog.implementation(for: provider) else { return [] }
        let context = self.makeSettingsContext(provider: provider)
        return impl.settingsFields(context: context)
            .filter { $0.isVisible?() ?? true }
    }

    private func extraSettingsModelLimits(for provider: UsageProvider) -> [ProviderSettingsModelLimitsDescriptor] {
        ProviderCatalog.implementation(for: provider)?
            .settingsModelLimits(context: self.makeSettingsContext(provider: provider)) ?? []
    }

    private func extraSettingsDirectoryLists(for provider: UsageProvider) -> [ProviderSettingsDirectoryListDescriptor] {
        ProviderCatalog.implementation(for: provider)?
            .settingsDirectoryLists(context: self.makeSettingsContext(provider: provider)) ?? []
    }

    private func extraSettingsActions(for provider: UsageProvider) -> [ProviderSettingsActionsDescriptor] {
        guard let impl = ProviderCatalog.implementation(for: provider) else { return [] }
        let context = self.makeSettingsContext(provider: provider)
        return impl.settingsActions(context: context)
            .filter { $0.isVisible?() ?? true }
    }

    private func extraSettingsOrganizations(
        for provider: UsageProvider) -> ProviderSettingsOrganizationsDescriptor?
    {
        guard let impl = ProviderCatalog.implementation(for: provider) else { return nil }
        let context = self.makeSettingsContext(provider: provider)
        return impl.settingsOrganizations(context: context)
    }

    func tokenAccountDescriptor(for provider: UsageProvider) -> ProviderSettingsTokenAccountsDescriptor? {
        guard let support = TokenAccountSupportCatalog.support(for: provider) else { return nil }
        let context = self.makeSettingsContext(provider: provider)
        let implementation = ProviderCatalog.implementation(for: provider)
        var descriptor = ProviderSettingsTokenAccountsDescriptor(
            id: "token-accounts-\(provider.rawValue)",
            title: support.title,
            subtitle: support.subtitle,
            placeholder: support.placeholder,
            provider: provider,
            isVisible: {
                ProviderCatalog.implementation(for: provider)?
                    .tokenAccountsVisibility(context: context, support: support)
                    ?? (!support.requiresManualCookieSource ||
                        !context.settings.tokenAccounts(for: provider).isEmpty)
            },
            accounts: { self.settings.tokenAccounts(for: provider) },
            activeIndex: {
                let data = self.settings.tokenAccountsData(for: provider)
                return data?.clampedActiveIndex() ?? 0
            },
            setActiveIndex: { index in
                self.settings.setActiveTokenAccountIndex(index, for: provider)
                Task { @MainActor in
                    await ProviderInteractionContext.$current.withValue(.userInitiated) {
                        await self.store.refreshProvider(provider, allowDisabled: true)
                    }
                }
            },
            showsOrganizationField: support.showsOrganizationField,
            showsTeamModeControls: support.showsTeamModeControls,
            addAccount: { label, token, usageScope, organizationID, workspaceID, claudeConfigDirectory in
                self.settings.addTokenAccount(
                    provider: provider,
                    label: label,
                    token: token,
                    usageScope: usageScope,
                    organizationID: organizationID,
                    workspaceID: workspaceID,
                    claudeConfigDirectory: claudeConfigDirectory)
                Task { @MainActor in
                    await ProviderInteractionContext.$current.withValue(.userInitiated) {
                        await self.store.refreshProvider(provider, allowDisabled: true)
                    }
                }
            },
            updateAccount: { accountID, usageScope, organizationID, workspaceID in
                self.settings.updateTokenAccount(
                    provider: provider,
                    accountID: accountID,
                    usageScope: usageScope,
                    organizationID: organizationID,
                    workspaceID: workspaceID)
                Task { @MainActor in
                    await ProviderInteractionContext.$current.withValue(.userInitiated) {
                        await self.store.refreshProvider(provider, allowDisabled: true)
                    }
                }
            },
            removeAccount: { accountID in
                self.settings.removeTokenAccount(provider: provider, accountID: accountID)
                Task { @MainActor in
                    await ProviderInteractionContext.$current.withValue(.userInitiated) {
                        await self.store.refreshProvider(provider, allowDisabled: true)
                    }
                }
            },
            primaryAddActionTitle: support.primaryAddActionTitle,
            primaryAddAction: support.primaryAddActionTitle.map { _ in {
                await implementation?.runTokenAccountPrimaryAction(context: context)
                await ProviderInteractionContext.$current.withValue(.userInitiated) {
                    await self.store.refreshProvider(provider, allowDisabled: true)
                }
            } },
            openConfigFile: {
                if implementation?.openTokenFile(context: context) == true {
                    return
                }
                self.settings.openTokenAccountsFile()
            },
            reloadFromDisk: {
                self.settings.reloadTokenAccounts()
                Task { @MainActor in
                    await ProviderInteractionContext.$current.withValue(.userInitiated) {
                        await self.store.refreshProvider(provider, allowDisabled: true)
                    }
                }
            })
        descriptor.editAccount = { accountID, label, token in
            self.settings.updateTokenAccount(provider: provider, accountID: accountID, label: label, token: token)
        }
        descriptor.moveAccount = { accountID, destination in
            self.settings.moveTokenAccount(provider: provider, accountID: accountID, to: destination)
        }
        // Provider-specific by design: only Claude accounts declare local transcript ownership.
        if provider == .claude {
            descriptor.claudeConfigDirectory = { accountID in
                Binding(
                    get: { self.settings.tokenAccounts(for: provider)
                        .first(where: { $0.id == accountID })?.claudeConfigDirectory
                    },
                    set: { directory in
                        self.settings.updateTokenAccount(
                            provider: provider, accountID: accountID, claudeConfigDirectory: .some(directory))
                    })
            }
        }
        return descriptor
    }

    /// Asks before removing a token account: removing it deletes the saved credential.
    func requestTokenAccountRemoval(
        _ account: ProviderTokenAccount,
        descriptor: ProviderSettingsTokenAccountsDescriptor)
    {
        self.activeConfirmation = ProviderSettingsConfirmationState(
            title: L("Remove token account?"),
            message: L("%@ and its saved credential will be removed from Tolkein.", account.displayName),
            confirmTitle: L("remove"),
            onConfirm: { descriptor.removeAccount(account.id) })
    }

    func makeSettingsContext(provider: UsageProvider) -> ProviderSettingsContext {
        ProviderSettingsContext(
            provider: provider,
            settings: self.settings,
            store: self.store,
            statusText: { id in
                self.settingsStatusTextByID[id]
            },
            setStatusText: { id, text in
                if let text {
                    self.settingsStatusTextByID[id] = text
                } else {
                    self.settingsStatusTextByID.removeValue(forKey: id)
                }
            },
            lastAppActiveRunAt: { id in
                self.settingsLastAppActiveRunAtByID[id]
            },
            setLastAppActiveRunAt: { id, date in
                if let date {
                    self.settingsLastAppActiveRunAtByID[id] = date
                } else {
                    self.settingsLastAppActiveRunAtByID.removeValue(forKey: id)
                }
            },
            requestConfirmation: { confirmation in
                self.activeConfirmation = ProviderSettingsConfirmationState(confirmation: confirmation)
            },
            runLoginFlow: {
                await self.runProviderLoginFlow(provider)
            })
    }

    func openAIWebDiagnostic(for provider: UsageProvider) -> String? {
        // Provider-specific by design: the OpenAI dashboard diagnostic comes from Codex's app-only web session.
        guard provider == .codex else { return nil }
        let diagnostic = self.store.codexConsumerProjectionIfNeeded(
            for: provider,
            surface: .liveCard)?.userFacingErrors.dashboard
        return PersonalInfoRedactor.redactEmails(in: diagnostic, isEnabled: self.settings.hidePersonalInfo)
    }

    /// Runs every provider toggle's "app became active" hook, as the old Providers pane did.
    func runSettingsDidBecomeActiveHooks() {
        for provider in UsageProvider.allCases {
            for toggle in self.extraSettingsToggles(for: provider) {
                guard let hook = toggle.onAppDidBecomeActive else { continue }
                Task { @MainActor in
                    await hook()
                }
            }
        }
    }

    // MARK: - Codex accounts

    func codexAccountsSectionState(for provider: UsageProvider) -> CodexAccountsSectionState? {
        // Provider-specific by design: managed Codex profiles own app-only account promotion and reauthentication
        // state.
        guard provider == .codex else { return nil }
        let projection = self.settings.codexVisibleAccountProjection
        let degradedNotice: CodexAccountsSectionNotice? = if projection.hasUnreadableAddedAccountStore {
            CodexAccountsSectionNotice(
                text: L("managed_account_storage_unreadable"),
                tone: .warning)
        } else {
            nil
        }

        return CodexAccountsSectionState(
            visibleAccounts: projection.visibleAccounts,
            activeVisibleAccountID: projection.activeVisibleAccountID,
            liveVisibleAccountID: projection.liveVisibleAccountID,
            hasUnreadableManagedAccountStore: projection.hasUnreadableAddedAccountStore,
            isAuthenticatingManagedAccount: self.managedCodexAccountCoordinator.isAuthenticatingManagedAccount,
            authenticatingManagedAccountID: self.managedCodexAccountCoordinator.authenticatingManagedAccountID,
            isRemovingManagedAccount: self.managedCodexAccountCoordinator.isRemovingManagedAccount,
            isAuthenticatingLiveAccount: self.isAuthenticatingLiveCodexAccount,
            isPromotingSystemAccount: self.codexAccountPromotionCoordinator.isPromotingSystemAccount,
            notice: self.codexAccountsNotice ?? degradedNotice,
            hidePersonalInfo: self.settings.hidePersonalInfo)
    }

    func selectCodexVisibleAccount(id: String) async {
        self.codexAccountsNotice = nil
        guard self.settings.selectCodexVisibleAccount(id: id) else { return }
        await self.refreshCodexProvider()
    }

    func requestCodexSystemVisibleAccount(id: String) async {
        self.codexAccountsNotice = nil
        guard let account = self.settings.codexVisibleAccountProjection.visibleAccounts.first(where: { $0.id == id }),
              let managedAccountID = account.storedAccountID
        else {
            return
        }

        let result = await self.codexAccountPromotionCoordinator.promote(managedAccountID: managedAccountID)
        switch result {
        case let .failure(error):
            self.codexAccountsNotice = CodexAccountsSectionNotice(text: error.message, tone: .warning)
        case let .success(promotion):
            self.codexAccountsNotice = promotion.daemonRestartNote.map { .init(text: $0, tone: .warning) }
        }
    }

    func addManagedCodexAccount() async {
        self.codexAccountsNotice = nil
        guard let state = self.codexAccountsSectionState(for: .codex), state.canAddAccount else {
            return
        }

        do {
            let account = try await self.managedCodexAccountCoordinator.authenticateManagedAccount()
            self.settings.selectAuthenticatedManagedCodexAccount(account)
            await self.refreshCodexProvider()
        } catch {
            self.codexAccountsNotice = self.codexAccountsNotice(for: error)
        }
    }

    func reauthenticateCodexAccount(_ account: CodexVisibleAccount) async {
        self.codexAccountsNotice = nil
        self.settings.invalidateCodexAccountReconciliationSnapshotCache()
        guard let state = self.codexAccountsSectionState(for: .codex),
              let current = state.visibleAccounts.first(where: { $0.id == account.id }),
              current.selectionSource == account.selectionSource,
              current.storedAccountID == account.storedAccountID,
              current.workspaceAccountID == account.workspaceAccountID,
              state.canReauthenticate(current)
        else { return }
        if case let .managedAccount(accountID) = current.selectionSource {
            do {
                _ = try await self.managedCodexAccountCoordinator
                    .authenticateManagedAccount(existingAccountID: accountID)
                await self.refreshCodexProvider()
            } catch {
                self.codexAccountsNotice = self.codexAccountsNotice(for: error)
            }
            return
        }

        guard current.selectionSource == .liveSystem else { return }

        self.isAuthenticatingLiveCodexAccount = true
        self.codexAccountPromotionCoordinator.setLiveReauthenticationInProgress(true)
        defer {
            self.isAuthenticatingLiveCodexAccount = false
            self.codexAccountPromotionCoordinator.setLiveReauthenticationInProgress(false)
        }

        let result = await self.codexAmbientLoginRunner.run(timeout: 120)
        if let info = CodexLoginAlertPresentation.alertInfo(for: result) {
            self.presentLoginAlert(title: info.title, message: info.message)
            return
        }

        await self.refreshCodexProvider()
    }

    func removeManagedCodexAccount(id: UUID) async {
        self.codexAccountsNotice = nil
        do {
            try await self.managedCodexAccountCoordinator.removeManagedAccount(id: id)
            await self.refreshCodexProvider()
        } catch {
            self.codexAccountsNotice = self.codexAccountsNotice(for: error)
        }
    }

    func requestManagedCodexAccountRemoval(_ account: CodexVisibleAccount) {
        guard let accountID = account.storedAccountID else { return }
        self.activeConfirmation = ProviderSettingsConfirmationState(
            title: L("remove_codex_account_title"),
            message: String(format: L("remove_account_message"), account.email),
            confirmTitle: L("remove"),
            onConfirm: {
                Task { @MainActor in
                    await self.removeManagedCodexAccount(id: accountID)
                }
            })
    }

    private func refreshCodexProvider() async {
        await ProviderInteractionContext.$current.withValue(.userInitiated) {
            await self.store.refreshCodexAccountScopedState(allowDisabled: true)
        }
    }

    private func codexAccountsNotice(for error: Error) -> CodexAccountsSectionNotice {
        if let error = error as? ManagedCodexAccountCoordinatorError,
           error == .authenticationInProgress
        {
            return CodexAccountsSectionNotice(
                text: L("managed_login_already_running"),
                tone: .warning)
        }

        if let error = error as? ManagedCodexAccountServiceError {
            return CodexAccountsSectionNotice(text: error.userFacingMessage, tone: .warning)
        }

        return CodexAccountsSectionNotice(
            text: error.localizedDescription,
            tone: .warning)
    }

    private func presentLoginAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = L(title)
        alert.informativeText = L(message)
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Confirmation

    func confirmActiveConfirmation() {
        guard let active = self.activeConfirmation else { return }
        active.onConfirm()
        self.activeConfirmation = nil
    }

    func dismissActiveConfirmation() {
        self.activeConfirmation = nil
    }
}

@MainActor
struct ProviderSettingsConfirmationState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void

    init(
        title: String,
        message: String,
        confirmTitle: String,
        onConfirm: @escaping () -> Void)
    {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
    }

    init(confirmation: ProviderSettingsConfirmation) {
        self.title = L(confirmation.title)
        self.message = L(confirmation.message)
        self.confirmTitle = L(confirmation.confirmTitle)
        self.onConfirm = confirmation.onConfirm
    }
}

struct ProviderErrorDisplay: Equatable {
    let title: String
    let preview: String
    let full: String
}
