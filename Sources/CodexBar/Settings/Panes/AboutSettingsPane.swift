import SwiftUI

/// About: version, updates, links and acknowledgements.
/// Shows the old `AboutPane` until the Internal UI rebuild replaces this file.
@MainActor
struct AboutSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        AboutPane(updater: self.context.updater, selection: self.context.selection)
    }
}

extension AboutSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.about
        let updates = L("section_updates")
        return [
            .paneTitle(pane),
            pane.searchEntry("automaticChecks", L("check_updates_auto"), keywords: updates),
            pane.searchEntry("automaticInstall", L("install_updates_auto"), keywords: updates),
            pane.searchEntry("updateChannel", L("update_channel"), keywords: updates),
            pane.searchEntry("checkForUpdates", L("check_for_updates"), keywords: updates),
            pane.searchEntry("acknowledgements", L("link_acknowledgements"), keywords: L("section_links")),
        ]
    }
}
