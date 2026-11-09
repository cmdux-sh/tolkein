import InternalUI
import SwiftUI

/// The Menu pane's agent sessions section: Stay Awake, the sessions list and its labels, and remote hosts.
@MainActor
struct AgentSessionsSettingsSection: View {
    @Bindable var settings: SettingsStore

    static var requiresAgentSessionsReason: String {
        L("settings_reason_requires_setting", L("agent_sessions_title"))
    }

    /// Why a remote-host setting is off: it needs agent sessions, then remote sessions.
    static func remoteHostsDisabledReason(agentSessionsEnabled: Bool, remoteEnabled: Bool) -> String? {
        if !agentSessionsEnabled { return self.requiresAgentSessionsReason }
        if !remoteEnabled { return L("settings_reason_requires_setting", L("agent_sessions_remote_title")) }
        return nil
    }

    var body: some View {
        let sessionsEnabled = self.settings.agentSessionsEnabled
        let remoteReason = Self.remoteHostsDisabledReason(
            agentSessionsEnabled: sessionsEnabled,
            remoteEnabled: self.settings.agentSessionsRemoteEnabled)
        IUSettingsSection(L("section_agent_sessions"), footer: L("agent_sessions_footer")) {
            IUSettingsToggleRow(
                L("Stay Awake"),
                subtitle: L("Prevent idle system sleep while a local agent process is running, even when idle. " +
                    "Uses battery power; does not prevent lid-close or display sleep."),
                isOn: self.$settings.stayAwakeEnabled)
                .settingsAnchor(MenuSettingsPane.SearchID.stayAwake)

            IUSettingsToggleRow(
                L("agent_sessions_title"),
                subtitle: L("agent_sessions_subtitle"),
                isOn: self.$settings.agentSessionsEnabled)
                .settingsAnchor(MenuSettingsPane.SearchID.agentSessions)

            IUSettingsRow(
                L("agent_session_labels_title"),
                subtitle: L("agent_session_labels_subtitle"),
                disabledReason: Self.requiresAgentSessionsReason)
            {
                IUPopUpButton(
                    MenuSettingsMenuOptions.agentSessionLabelStyles.map { ($0, $0.label) },
                    selection: self.$settings.agentSessionLabelStyle)
                    .accessibilityLabel(L("agent_session_labels_title"))
            }
            .disabled(!sessionsEnabled)
            .settingsAnchor(MenuSettingsPane.SearchID.agentSessionLabels)

            IUSettingsToggleRow(
                L("agent_sessions_remote_title"),
                subtitle: L("agent_sessions_remote_subtitle"),
                disabledReason: Self.requiresAgentSessionsReason,
                isOn: self.$settings.agentSessionsRemoteEnabled)
                .disabled(!sessionsEnabled)
                .settingsAnchor(MenuSettingsPane.SearchID.agentSessionsRemote)

            IUSettingsToggleRow(
                L("agent_sessions_hide_unreachable_title"),
                subtitle: L("agent_sessions_hide_unreachable_subtitle"),
                disabledReason: remoteReason,
                isOn: self.$settings.agentSessionsHideUnreachableHosts)
                .disabled(remoteReason != nil)
                .settingsAnchor(MenuSettingsPane.SearchID.agentSessionsHideUnreachable)

            AgentSessionHostsEditor(settings: self.settings)
        }
    }
}

/// Extra SSH hosts to check for agent sessions, typed as a comma-separated list.
@MainActor
struct AgentSessionHostsEditor: View {
    static let inputFormatHint = "user@host, user@host"

    @Bindable var settings: SettingsStore

    var body: some View {
        let reason = AgentSessionsSettingsSection.remoteHostsDisabledReason(
            agentSessionsEnabled: self.settings.agentSessionsEnabled,
            remoteEnabled: self.settings.agentSessionsRemoteEnabled)
        IUSettingsRow(
            L("agent_sessions_hosts_title"),
            subtitle: L("agent_sessions_hosts_help"),
            disabledReason: reason)
        {
            IUTextField(Self.inputFormatHint, text: self.$settings.agentSessionsManualHosts)
                .frame(width: IUSize.settingsField)
                .accessibilityLabel(L("agent_sessions_hosts_title"))
                .help(L("agent_sessions_hosts_help"))
        }
        .disabled(reason != nil)
        .settingsAnchor(MenuSettingsPane.SearchID.agentSessionHosts)
    }
}
