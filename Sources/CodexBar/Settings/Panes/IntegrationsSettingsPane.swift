import SwiftUI

/// Integrations: the local HTTP server, the command-line tool and Hooks.
/// Stacks the old HTTP server and CLI sections from Advanced with the old Hooks pane until the Internal UI rebuild
/// replaces this file.
@MainActor
struct IntegrationsSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        Form {
            HTTPServerSection(controller: self.context.settings.httpServer)
            CommandLineInstallSection()
            HooksSections(settings: self.context.settings)
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollContentBackground(.hidden)
    }
}

extension IntegrationsSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.integrations
        let httpServer = L("http_server_title")
        let hooks = L("tab_hooks")
        let commandLine = L("section_command_line")
        let cliSubtitle = L("install_cli_subtitle")
        let advanced = SettingsSearchEntry.formerAdvancedKeyword
        return [
            .paneTitle(pane, keywords: advanced),
            pane.searchEntry("httpServer", httpServer, keywords: L("http_server_enable"), advanced),
            pane.searchEntry("httpServerToken", L("http_server_token"), keywords: httpServer, advanced),
            pane.searchEntry("installCLI", L("install_cli"), keywords: commandLine, cliSubtitle, advanced),
            pane.searchEntry("hooks", L("hooks_enable_title"), keywords: hooks, L("hooks_enable_subtitle")),
            pane.searchEntry("hookRules", L("hooks_rules_header"), keywords: hooks),
        ]
    }
}
