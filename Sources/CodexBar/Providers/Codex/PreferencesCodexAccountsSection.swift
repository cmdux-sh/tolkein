import Foundation
import InternalUI
import SwiftUI

protocol CodexAmbientLoginRunning: Sendable {
    func run(timeout: TimeInterval) async -> CLILoginRunner.Result
}

struct DefaultCodexAmbientLoginRunner: CodexAmbientLoginRunning {
    func run(timeout: TimeInterval) async -> CLILoginRunner.Result {
        await CodexLoginRunner.run(timeout: timeout)
    }
}

struct CodexAccountsSectionNotice: Equatable {
    enum Tone: Equatable {
        case secondary
        case warning
    }

    let text: String
    let tone: Tone
}

struct CodexAccountsSectionState: Equatable {
    let visibleAccounts: [CodexVisibleAccount]
    let activeVisibleAccountID: String?
    let liveVisibleAccountID: String?
    let hasUnreadableManagedAccountStore: Bool
    let isAuthenticatingManagedAccount: Bool
    let authenticatingManagedAccountID: UUID?
    let isRemovingManagedAccount: Bool
    let isAuthenticatingLiveAccount: Bool
    let isPromotingSystemAccount: Bool
    let notice: CodexAccountsSectionNotice?
    var hidePersonalInfo = false

    var showsActivePicker: Bool {
        self.visibleAccounts.count > 1
    }

    var singleVisibleAccount: CodexVisibleAccount? {
        self.visibleAccounts.count == 1 ? self.visibleAccounts.first : nil
    }

    var systemVisibleAccount: CodexVisibleAccount? {
        guard let liveVisibleAccountID else { return nil }
        return self.visibleAccounts.first { $0.id == liveVisibleAccountID }
    }

    var showsSystemPicker: Bool {
        self.visibleAccounts.count > 1 || (self.liveVisibleAccountID == nil && !self.visibleAccounts.isEmpty)
    }

    var systemDisplayName: String {
        self.systemVisibleAccount.map { self.displayName(for: $0) } ?? L("No system account")
    }

    func displayName(for account: CodexVisibleAccount) -> String {
        guard self.hidePersonalInfo else { return account.displayName }
        return CodexAccountSwitcherLabeling.label(
            for: account,
            ordinal: CodexAccountSwitcherLabeling.ordinals(for: self.visibleAccounts)[account.id],
            hidePersonalInfo: true)
    }

    var canAddAccount: Bool {
        !self.hasUnreadableManagedAccountStore && !self.hasAccountOperationInFlight
    }

    private var hasAccountOperationInFlight: Bool {
        self.isAuthenticatingManagedAccount || self.isRemovingManagedAccount ||
            self.isAuthenticatingLiveAccount || self.isPromotingSystemAccount
    }

    var addAccountTitle: String {
        if self.isAuthenticatingManagedAccount, self.authenticatingManagedAccountID == nil {
            return L("Adding Account…")
        }
        return L("Add Account")
    }

    func showsLiveBadge(for account: CodexVisibleAccount) -> Bool {
        account.isLive
    }

    var isSystemSelectionDisabled: Bool {
        !self.canAddAccount
    }

    func canPromoteToSystem(_ account: CodexVisibleAccount) -> Bool {
        guard self.isSystemSelectionDisabled == false else { return false }
        guard account.id != self.liveVisibleAccountID else { return false }
        return account.storedAccountID != nil
    }

    func canReauthenticate(_ account: CodexVisibleAccount) -> Bool {
        guard account.canReauthenticate, !self.hasAccountOperationInFlight else { return false }
        switch account.selectionSource {
        case .managedAccount:
            return !self.hasUnreadableManagedAccountStore
        case .liveSystem:
            return true
        case .profileHome:
            return false
        }
    }

    func canRemove(_ account: CodexVisibleAccount) -> Bool {
        account.canRemove && self.canAddAccount
    }

    func reauthenticateTitle(for account: CodexVisibleAccount) -> String {
        if case let .managedAccount(accountID) = account.selectionSource,
           self.isAuthenticatingManagedAccount,
           self.authenticatingManagedAccountID == accountID
        {
            return L("Re-authenticating…")
        }
        if account.selectionSource == .liveSystem, self.isAuthenticatingLiveAccount {
            return L("Re-authenticating…")
        }
        return L("Re-auth")
    }
}

@MainActor
struct CodexAccountsSectionView: View {
    let state: CodexAccountsSectionState
    let setActiveVisibleAccount: (String) -> Void
    let reauthenticateAccount: (CodexVisibleAccount) -> Void
    let removeAccount: (CodexVisibleAccount) -> Void
    let requestSystemVisibleAccount: (String) -> Void
    let addAccount: () -> Void
    var renameAccount: (CodexVisibleAccount, String) -> Void = { _, _ in }

    private var isBusy: Bool {
        self.state.isAuthenticatingManagedAccount ||
            self.state.isRemovingManagedAccount ||
            self.state.isAuthenticatingLiveAccount ||
            self.state.isPromotingSystemAccount
    }

    private var accountOptions: [(String, String)] {
        self.state.visibleAccounts.map { ($0.id, self.state.displayName(for: $0)) }
    }

    var body: some View {
        IUSettingsSection(L("Accounts")) {
            if let selection = self.activeSelectionBinding {
                IUSettingsRow(
                    L("Tolkein follows"),
                    subtitle: L("Choose which Codex account Tolkein should follow."))
                {
                    IUPopUpButton(self.accountOptions, selection: selection)
                }
                .disabled(self.isBusy)
                self.systemRow(selection: self.systemSelectionBinding)
                    .disabled(self.isBusy)
            } else if let account = self.state.singleVisibleAccount {
                IUSettingsValueRow(L("Account"), value: self.state.displayName(for: account))
                self.systemRow(selection: nil)
            }

            if self.state.visibleAccounts.isEmpty {
                IUText(L("No Codex accounts detected yet."), role: .caption, muted: true)
                    .providerSettingsRow()
            } else {
                ForEach(self.state.visibleAccounts) { account in
                    CodexAccountsSectionRowView(
                        account: account,
                        displayName: self.state.displayName(for: account),
                        hidePersonalInfo: self.state.hidePersonalInfo,
                        showsSystemBadge: self.state.showsLiveBadge(for: account),
                        reauthenticateTitle: self.state.reauthenticateTitle(for: account),
                        canReauthenticate: self.state.canReauthenticate(account),
                        canRemove: self.state.canRemove(account),
                        onReauthenticate: { self.reauthenticateAccount(account) },
                        onRemove: { self.removeAccount(account) },
                        onRename: { self.renameAccount(account, $0) })
                }
            }

            HStack(spacing: IUSpace.unit * 2) {
                if let notice = self.state.notice {
                    if notice.tone == .warning {
                        IUStatusLabel(notice.text, tone: .warning)
                            .help(notice.text)
                    } else {
                        IUText(notice.text, role: .caption, muted: true)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button(self.state.addAccountTitle) {
                    self.addAccount()
                }
                .buttonStyle(.iu())
                .disabled(self.state.canAddAccount == false)
            }
            .providerSettingsRow()
        }
    }

    private var activeSelectionBinding: Binding<String>? {
        guard self.state.showsActivePicker else { return nil }
        let fallbackID = self.state.activeVisibleAccountID ?? self.state.visibleAccounts.first?.id
        guard let fallbackID else { return nil }
        return Binding(
            get: { self.state.activeVisibleAccountID ?? fallbackID },
            set: { self.setActiveVisibleAccount($0) })
    }

    private var systemSelectionBinding: Binding<String>? {
        guard self.state.showsSystemPicker else { return nil }
        guard let liveVisibleAccountID = self.state.liveVisibleAccountID else { return nil }
        return Binding(
            get: { self.state.liveVisibleAccountID ?? liveVisibleAccountID },
            set: { self.requestSystemVisibleAccount($0) })
    }

    private func systemRow(selection: Binding<String>?) -> some View {
        IUSettingsRow(L("System"), subtitle: L("The default Codex account on this Mac.")) {
            if let selection {
                IUPopUpButton(self.accountOptions, selection: selection)
                    .disabled(self.state.isSystemSelectionDisabled)
            } else if self.state.showsSystemPicker {
                Menu(self.state.systemDisplayName) {
                    ForEach(self.state.visibleAccounts) { account in
                        Button(self.state.displayName(for: account)) {
                            self.requestSystemVisibleAccount(account.id)
                        }
                        .disabled(self.state.canPromoteToSystem(account) == false)
                    }
                }
                .fixedSize()
                .disabled(self.state.isSystemSelectionDisabled)
            } else {
                IUText(self.state.systemDisplayName, muted: self.state.systemVisibleAccount == nil)
            }
        }
    }
}

private struct CodexAccountsSectionRowView: View {
    let account: CodexVisibleAccount
    let displayName: String
    let hidePersonalInfo: Bool
    let showsSystemBadge: Bool
    let reauthenticateTitle: String
    let canReauthenticate: Bool
    let canRemove: Bool
    let onReauthenticate: () -> Void
    let onRemove: () -> Void
    let onRename: (String) -> Void
    @State private var isRenaming = false
    @State private var editedName = ""

    private var title: String {
        self.showsSystemBadge ? "\(self.displayName) \(L("(System)"))" : self.displayName
    }

    private var subtitle: String? {
        var lines: [String] = []
        if self.account.customName != nil, !self.hidePersonalInfo {
            lines.append(self.account.withCustomName(nil).displayName)
        }
        if let health = self.account.authenticationHealthLabel {
            lines.append(health)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    var body: some View {
        IUSettingsRow(self.title, subtitle: self.subtitle) {
            HStack(spacing: IUSpace.unit * 2) {
                Button(L("Rename")) {
                    self.editedName = self.account.customName ?? ""
                    self.isRenaming = true
                }
                .buttonStyle(.iu())
                .disabled(self.hidePersonalInfo)

                if self.account.canReauthenticate {
                    Button(self.reauthenticateTitle) {
                        self.onReauthenticate()
                    }
                    .buttonStyle(.iu())
                    .disabled(self.canReauthenticate == false)
                }

                if self.account.canRemove {
                    Button(L("Remove")) {
                        self.onRemove()
                    }
                    .buttonStyle(.iu())
                    .disabled(self.canRemove == false)
                }
            }
        }
        .alert(L("Rename account"), isPresented: self.$isRenaming) {
            TextField(L("Account name"), text: self.$editedName)
            Button(L("Save")) {
                self.onRename(self.editedName)
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Leave blank to use the default name."))
        }
        .onChange(of: self.hidePersonalInfo) {
            if self.hidePersonalInfo { self.isRenaming = false }
        }
    }
}
