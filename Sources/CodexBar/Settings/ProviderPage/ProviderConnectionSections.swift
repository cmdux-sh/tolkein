import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

/// The Sign-in & connection group: connection pickers, actions and fields in one section, then token accounts,
/// directory lists, model limits, organizations, Codex accounts and the OpenAI web diagnostic in their own.
@MainActor
struct ProviderConnectionSections: View {
    private struct ModelLimitsIdentity: Hashable {
        let id: String
        let scope: ProviderModelRateLimitScope?
    }

    let content: ProviderSettingsPageContent
    let model: ProviderSettingsPageModel

    var body: some View {
        let pickers = self.content.connectionPickers
        if !pickers.isEmpty || !self.content.actions.isEmpty || !self.content.fields.isEmpty {
            MacSettingsSection(ProviderSettingsPageSection.connection.title) {
                ForEach(pickers) { picker in
                    ProviderSettingsPickerRow(picker: picker)
                }
                ForEach(self.content.actions) { descriptor in
                    ProviderSettingsActionsRow(descriptor: descriptor)
                }
                ForEach(self.content.fields) { field in
                    ProviderSettingsFieldRow(field: field)
                }
            }
        }

        if let tokenAccounts = self.content.tokenAccounts {
            ProviderTokenAccountsSection(
                descriptor: tokenAccounts,
                requestRemoval: { account in
                    self.model.requestTokenAccountRemoval(account, descriptor: tokenAccounts)
                })
        }

        ForEach(self.content.directoryLists) { descriptor in
            ProviderDirectoryListSection(descriptor: descriptor)
        }

        ForEach(self.content.modelLimits) { descriptor in
            ProviderModelLimitsSection(descriptor: descriptor)
                .id(ModelLimitsIdentity(id: descriptor.id, scope: descriptor.scope))
        }

        if let organizations = self.content.organizations {
            ProviderOrganizationsSection(descriptor: organizations)
        }

        if let state = self.content.codexAccounts {
            CodexAccountsSectionView(
                state: state,
                setActiveVisibleAccount: { visibleAccountID in
                    Task { @MainActor in
                        await self.model.selectCodexVisibleAccount(id: visibleAccountID)
                    }
                },
                reauthenticateAccount: { account in
                    Task { @MainActor in
                        await self.model.reauthenticateCodexAccount(account)
                    }
                },
                removeAccount: { account in
                    self.model.requestManagedCodexAccountRemoval(account)
                },
                requestSystemVisibleAccount: { visibleAccountID in
                    Task { @MainActor in
                        await self.model.requestCodexSystemVisibleAccount(id: visibleAccountID)
                    }
                },
                addAccount: {
                    Task { @MainActor in
                        await self.model.addManagedCodexAccount()
                    }
                },
                renameAccount: { account, name in
                    self.model.settings.renameCodexAccount(account, to: name)
                })
        }

        if let diagnostic = self.content.connectionDiagnostic {
            MacSettingsSection(L("OpenAI web extras")) {
                ProviderSettingsCaptionRow(diagnostic)
            }
        }
    }
}

// MARK: - Directory lists

/// A provider's opt-in folder list: one row per folder with Remove, and Add folder….
@MainActor
struct ProviderDirectoryListSection: View {
    let descriptor: ProviderSettingsDirectoryListDescriptor
    @Binding private var paths: [String]

    init(descriptor: ProviderSettingsDirectoryListDescriptor) {
        self.descriptor = descriptor
        self._paths = descriptor.binding
    }

    var body: some View {
        MacSettingsSection(L(self.descriptor.title), footer: L(self.descriptor.subtitle)) {
            ForEach(Array(self.paths.enumerated()), id: \.offset) { _, path in
                HStack(spacing: MacSpace.unit * 2) {
                    Text(path)
                        .font(MacTextRole.body.font)
                        .foregroundStyle(MacColor.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                    Spacer(minLength: MacSpace.settingsRowPaddingX)
                    Button(L("Remove")) {
                        self.paths.removeAll { $0 == path }
                    }
                    .buttonStyle(.mac())
                    .accessibilityLabel(Text("\(L("Remove")) \(path)"))
                }
                .providerSettingsRow()
            }
            ProviderSettingsTrailingButtonsRow {
                Button(L("Add folder…")) {
                    Task { @MainActor in
                        let panel = NSOpenPanel()
                        panel.title = L(self.descriptor.title)
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = true
                        panel.showsHiddenFiles = true
                        guard await panel.begin() == .OK else { return }
                        var paths = self.paths
                        for url in panel.urls where !paths.contains(url.path) {
                            paths.append(url.path)
                        }
                        self.paths = paths
                    }
                }
                .buttonStyle(.mac())
            }
        }
    }
}

/// The Claude config directory a token account's local transcripts come from: the folder (flagged when it is
/// missing or unreadable), Add folder… and Remove.
@MainActor
struct TokenAccountDirectoryRow: View {
    @Binding var path: String?

    var body: some View {
        MacSettingsRow(L("Claude config directory"), subtitle: self.path) {
            HStack(spacing: MacSpace.unit * 2) {
                if let path, !Self.isAvailable(path) {
                    MacStatusLabel(L("Unavailable"), tone: .warning)
                }
                Button(L("Add folder…")) {
                    Task { @MainActor in
                        let panel = NSOpenPanel()
                        panel.title = L("Claude config directory")
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.showsHiddenFiles = true
                        guard await panel.begin() == .OK, let url = panel.url else { return }
                        self.path = url.path
                    }
                }
                .buttonStyle(.mac())
                if self.path != nil {
                    Button(L("Remove")) { self.path = nil }
                        .buttonStyle(.mac())
                }
            }
        }
        .help(L("cost_estimate_hint"))
    }

    static func isAvailable(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory)
            && directory.boolValue && FileManager.default.isReadableFile(atPath: path)
    }
}

// MARK: - Organizations

/// Extra account scopes a provider can include (such as Kilo organizations), with Refresh organizations.
@MainActor
struct ProviderOrganizationsSection: View {
    let descriptor: ProviderSettingsOrganizationsDescriptor
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    var body: some View {
        let entries = self.descriptor.entries()
        let subtitle = self.descriptor.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        MacSettingsSection(L(self.descriptor.title), footer: subtitle.isEmpty ? nil : L(subtitle)) {
            if entries.allSatisfy(\.isLocked) {
                ProviderSettingsCaptionRow(L("No organizations loaded. Click Refresh after setting your API key."))
            } else {
                ForEach(entries) { entry in
                    let entrySubtitle = entry.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    MacSettingsToggleRow(
                        entry.localizesTitle ? L(entry.title) : entry.title,
                        subtitle: entrySubtitle.isEmpty ? nil
                            : (entry.localizesSubtitle ? L(entrySubtitle) : entrySubtitle),
                        isOn: Binding(
                            get: { entry.isEnabled },
                            set: { newValue in
                                self.descriptor.onToggle(entry.id, newValue)
                            }))
                        .disabled(entry.isLocked)
                }
            }

            HStack(spacing: MacSpace.unit * 2) {
                if let errorMessage, !errorMessage.isEmpty {
                    MacStatusLabel(errorMessage, tone: .error)
                        .help(errorMessage)
                }
                Spacer(minLength: 0)
                Button(L("Refresh organizations")) {
                    Task { @MainActor in
                        self.isRefreshing = true
                        let result = await self.descriptor.onRefresh()
                        self.isRefreshing = false
                        self.errorMessage = result.success ? nil : result.errorMessage
                    }
                }
                .buttonStyle(.mac())
                .disabled(!self.descriptor.canRefresh() || self.isRefreshing)
            }
            .providerSettingsRow()
        }
    }
}
