import CodexBarCore
import InternalUI
import SwiftUI

/// Team mode for a token account (z.ai): personal, or a team with its organization and project IDs.
struct ProviderTokenAccountTeamDraft: Equatable {
    var teamMode: Bool
    var organizationID: String
    var projectID: String

    static let personal = Self(teamMode: false, organizationID: "", projectID: "")

    init(teamMode: Bool, organizationID: String, projectID: String) {
        self.teamMode = teamMode
        self.organizationID = organizationID
        self.projectID = projectID
    }

    init(account: ProviderTokenAccount) {
        let teamMode = account.sanitizedUsageScope?.lowercased() == "team"
        self.init(
            teamMode: teamMode,
            organizationID: teamMode ? (account.sanitizedOrganizationID ?? "") : "",
            projectID: teamMode ? (account.sanitizedWorkspaceID ?? "") : "")
    }

    func normalizedForPersistence() -> Self {
        guard self.teamMode else { return .personal }
        return Self(
            teamMode: true,
            organizationID: self.organizationID.trimmingCharacters(in: .whitespacesAndNewlines),
            projectID: self.projectID.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Team mode needs both IDs.
    var isIncomplete: Bool {
        let normalized = self.normalizedForPersistence()
        return normalized.teamMode && (normalized.organizationID.isEmpty || normalized.projectID.isEmpty)
    }

    /// Whether applying this draft over `original` would do nothing or save an incomplete team.
    static func isApplyDisabled(draft: Self, original: Self) -> Bool {
        guard draft.normalizedForPersistence() != original.normalizedForPersistence() else { return true }
        return draft.isIncomplete
    }
}

/// The team-mode rows, shared by the add form and the account editor: the Team mode switch and, while it is on, the
/// organization and project IDs.
struct ProviderTokenAccountTeamRows: View {
    @Binding var draft: ProviderTokenAccountTeamDraft

    var body: some View {
        MacSettingsToggleRow(L("Team mode"), isOn: self.$draft.teamMode)
        if self.draft.teamMode {
            MacSettingsRow(L("Organization ID")) {
                ProviderTextField(L("Organization ID"), text: self.$draft.organizationID)
                    .frame(width: MacSize.settingsField)
            }
            MacSettingsRow(L("Project ID")) {
                ProviderTextField(L("Project ID"), text: self.$draft.projectID)
                    .frame(width: MacSize.settingsField)
            }
        }
    }
}

/// A provider's token accounts: which one is active, each account with Edit, reorder and Remove (which asks first),
/// the add form, and the token file actions.
@MainActor
struct ProviderTokenAccountsSection: View {
    /// The add form's values before they are saved.
    struct NewAccountDraft: Equatable {
        var label = ""
        var token = ""
        var organizationID = ""
        var team = ProviderTokenAccountTeamDraft.personal
        var claudeConfigDirectory: String?
    }

    let descriptor: ProviderSettingsTokenAccountsDescriptor
    let requestRemoval: (ProviderTokenAccount) -> Void
    @State private var newAccount = NewAccountDraft()
    @State private var editingAccountID: UUID?
    @State private var editLabel = ""
    @State private var editToken = ""
    @State private var editTeam = ProviderTokenAccountTeamDraft.personal

    var body: some View {
        let accounts = self.descriptor.accounts()
        let subtitle = self.descriptor.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        MacSettingsSection(L(self.descriptor.title), footer: subtitle.isEmpty ? nil : L(subtitle)) {
            if accounts.isEmpty {
                ProviderSettingsCaptionRow(L("No token accounts yet."))
            } else {
                if accounts.count > 1 {
                    MacSettingsRow(L("Active")) {
                        MacPopUpButton(
                            accounts.enumerated().map { ($0.offset, $0.element.displayName) },
                            selection: Binding(
                                get: { Self.activeIndex(self.descriptor.activeIndex(), accountCount: accounts.count) },
                                set: { self.descriptor.setActiveIndex($0) }))
                    }
                }
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    self.accountRow(account, index: index, count: accounts.count)
                    if self.editingAccountID == account.id {
                        self.editorRows(account)
                    }
                    if let directory = self.descriptor.claudeConfigDirectory {
                        TokenAccountDirectoryRow(path: directory(account.id))
                    }
                }
            }

            if self.descriptor.primaryAddAction == nil {
                self.addFormRows
            }

            HStack(spacing: MacSpace.unit * 2) {
                Button(L("Open token file")) { self.descriptor.openConfigFile() }
                    .buttonStyle(.mac(.plain))
                Button(L("Reload")) { self.descriptor.reloadFromDisk() }
                    .buttonStyle(.mac(.plain))
                Spacer(minLength: 0)
                if let title = self.descriptor.primaryAddActionTitle,
                   let action = self.descriptor.primaryAddAction
                {
                    Button(L(title)) {
                        Task { @MainActor in
                            await action()
                        }
                    }
                    .buttonStyle(.mac(.primary))
                }
            }
            .providerSettingsRow()
        }
    }

    // MARK: Accounts

    private var canEditCredentials: Bool {
        self.descriptor.primaryAddAction == nil && self.descriptor.editAccount != nil
    }

    private func accountRow(_ account: ProviderTokenAccount, index: Int, count: Int) -> some View {
        MacSettingsRow(account.displayName, subtitle: self.accountSubtitle(account)) {
            HStack(spacing: MacSpace.unit * 2) {
                if self.canEditCredentials || self.descriptor.showsTeamModeControls {
                    Button(L("Edit")) { self.beginEditing(account) }
                        .buttonStyle(.mac())
                        .disabled(self.editingAccountID == account.id)
                }
                if let move = self.descriptor.moveAccount {
                    Button {
                        move(account.id, index - 1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.mac())
                    .help(L("Move up"))
                    .accessibilityLabel(L("Move up"))
                    .disabled(index == 0)
                    Button {
                        move(account.id, index + 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.mac())
                    .help(L("Move down"))
                    .accessibilityLabel(L("Move down"))
                    .disabled(index == count - 1)
                }
                Button(L("Remove")) { self.requestRemoval(account) }
                    .buttonStyle(.mac())
            }
        }
    }

    private func accountSubtitle(_ account: ProviderTokenAccount) -> String? {
        guard self.descriptor.showsTeamModeControls else { return nil }
        let team = ProviderTokenAccountTeamDraft(account: account)
        guard team.teamMode else { return L("Personal") }
        let ids = [team.organizationID, team.projectID].filter { !$0.isEmpty }.joined(separator: " / ")
        return ids.isEmpty ? L("Team mode") : "\(L("Team mode")) · \(ids)"
    }

    private func beginEditing(_ account: ProviderTokenAccount) {
        self.editingAccountID = account.id
        self.editLabel = account.label
        self.editToken = ""
        self.editTeam = ProviderTokenAccountTeamDraft(account: account)
    }

    @ViewBuilder
    private func editorRows(_ account: ProviderTokenAccount) -> some View {
        if self.canEditCredentials {
            MacSettingsRow(L("Label")) {
                ProviderTextField(L("Label"), text: self.$editLabel)
                    .frame(width: MacSize.settingsField)
            }
            MacSettingsRow(L("Token"), subtitle: L("Leave blank to keep the saved credential.")) {
                ProviderTextField(L(self.descriptor.placeholder), text: self.$editToken, isSecure: true)
                    .frame(width: MacSize.settingsField)
            }
        }
        if self.descriptor.showsTeamModeControls {
            ProviderTokenAccountTeamRows(draft: self.$editTeam)
        }
        ProviderSettingsTrailingButtonsRow {
            Button(L("Cancel")) { self.endEditing() }
                .buttonStyle(.mac())
                .keyboardShortcut(.cancelAction)
            Button(L("Save")) { self.saveEdits(account) }
                .buttonStyle(.mac(.primary))
                .disabled(self.isSaveDisabled(account))
        }
    }

    private func isSaveDisabled(_ account: ProviderTokenAccount) -> Bool {
        if self.canEditCredentials, self.editLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        guard self.descriptor.showsTeamModeControls else { return false }
        let original = ProviderTokenAccountTeamDraft(account: account)
        let changed = self.editTeam.normalizedForPersistence() != original.normalizedForPersistence()
        if !self.canEditCredentials, !changed { return true }
        return changed && self.editTeam.isIncomplete
    }

    private func saveEdits(_ account: ProviderTokenAccount) {
        guard !self.isSaveDisabled(account) else { return }
        if self.canEditCredentials {
            let token = self.editToken.trimmingCharacters(in: .whitespacesAndNewlines)
            self.descriptor.editAccount?(account.id, self.editLabel, token.isEmpty ? nil : token)
        }
        let original = ProviderTokenAccountTeamDraft(account: account)
        if self.descriptor.showsTeamModeControls,
           !ProviderTokenAccountTeamDraft.isApplyDisabled(draft: self.editTeam, original: original)
        {
            let normalized = self.editTeam.normalizedForPersistence()
            self.descriptor.updateAccount(
                account.id,
                normalized.teamMode ? "team" : "personal",
                normalized.teamMode ? normalized.organizationID : nil,
                normalized.teamMode ? normalized.projectID : nil)
        }
        self.endEditing()
    }

    private func endEditing() {
        self.editingAccountID = nil
        self.editToken = ""
    }

    static func activeIndex(_ index: Int, accountCount: Int) -> Int {
        min(max(0, index), max(0, accountCount - 1))
    }

    // MARK: Add form

    @ViewBuilder
    private var addFormRows: some View {
        MacSettingsRow(L("Label")) {
            ProviderTextField(L("Label"), text: self.$newAccount.label)
                .frame(width: MacSize.settingsField)
        }
        MacSettingsRow(L("Token")) {
            ProviderTextField(L(self.descriptor.placeholder), text: self.$newAccount.token, isSecure: true)
                .frame(width: MacSize.settingsField)
        }
        if self.descriptor.showsOrganizationField {
            MacSettingsRow(
                L("Org ID (optional)"),
                subtitle: L("Optional organization ID for accounts linked to multiple Anthropic organizations."))
            {
                ProviderTextField(L("Org ID (optional)"), text: self.$newAccount.organizationID)
                    .frame(width: MacSize.settingsField)
            }
        }
        if self.descriptor.showsTeamModeControls {
            ProviderTokenAccountTeamRows(draft: self.$newAccount.team)
        }
        if self.descriptor.claudeConfigDirectory != nil {
            TokenAccountDirectoryRow(path: self.$newAccount.claudeConfigDirectory)
        }
        ProviderSettingsTrailingButtonsRow {
            Button(L("Add")) { self.addAccount() }
                .buttonStyle(.mac(.primary))
                .disabled(Self.isAddDisabled(
                    label: self.newAccount.label,
                    token: self.newAccount.token,
                    showsTeamModeControls: self.descriptor.showsTeamModeControls,
                    teamMode: self.newAccount.team.teamMode,
                    teamContext: (
                        organizationID: self.newAccount.team.organizationID,
                        projectID: self.newAccount.team.projectID)))
        }
    }

    private func addAccount() {
        let draft = self.newAccount
        guard !Self.isAddDisabled(
            label: draft.label,
            token: draft.token,
            showsTeamModeControls: self.descriptor.showsTeamModeControls,
            teamMode: draft.team.teamMode,
            teamContext: (organizationID: draft.team.organizationID, projectID: draft.team.projectID))
        else { return }
        let label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = draft.token.trimmingCharacters(in: .whitespacesAndNewlines)
        let teamMode = self.descriptor.showsTeamModeControls && draft.team.teamMode
        let team = draft.team.normalizedForPersistence()
        let organizationID = self.descriptor.showsOrganizationField
            ? draft.organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let usageScope = self.descriptor.showsTeamModeControls ? (teamMode ? "team" : "personal") : nil
        let accountOrganizationID = if teamMode {
            team.organizationID.isEmpty ? nil : team.organizationID
        } else {
            organizationID.isEmpty ? nil : organizationID
        }
        let accountWorkspaceID = teamMode && !team.projectID.isEmpty ? team.projectID : nil
        self.descriptor.addAccount(
            label,
            token,
            usageScope,
            accountOrganizationID,
            accountWorkspaceID,
            self.descriptor.claudeConfigDirectory == nil ? nil : draft.claudeConfigDirectory)
        self.newAccount = NewAccountDraft()
    }

    static func isAddDisabled(
        label: String,
        token: String,
        showsTeamModeControls: Bool,
        teamMode: Bool,
        teamContext: (organizationID: String, projectID: String)) -> Bool
    {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !token.isEmpty else { return true }
        guard showsTeamModeControls, teamMode else { return false }
        return teamContext.organizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            teamContext.projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
