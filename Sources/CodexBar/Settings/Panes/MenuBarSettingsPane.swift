import SwiftUI

/// Menu Bar: the status item's icon style, layout, merged icon and animation.
/// Shows the old `MenuBarPane` until the Internal UI rebuild replaces this file.
@MainActor
struct MenuBarSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        MenuBarPane(settings: self.context.settings, store: self.context.store)
    }
}

extension MenuBarSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.menuBar
        let icon = L("section_icon")
        let combinedIcon = L("section_combined_icon")
        let animation = L("section_animation")
        return [
            .paneTitle(pane),
            pane.searchEntry("iconStyle", L("menu_bar_style_title"), keywords: icon),
            pane.searchEntry("inactiveDisplayContrast", L("menu_bar_inactive_display_contrast_title"), keywords: icon),
            pane.searchEntry("colorPace", L("Color Pace Indicator"), keywords: icon),
            pane.searchEntry("paceSign", L("Pace sign"), keywords: icon),
            pane.searchEntry("colorByProvider", L("Color by provider"), keywords: icon),
            pane.searchEntry("layout", L("menu_bar_layout_title")),
            pane.searchEntry("mergeIcons", L("merge_icons_title"), keywords: combinedIcon, L("merge_icons_subtitle")),
            pane.searchEntry("mergedIconStyle", L("merged_icon_style_title"), keywords: combinedIcon),
            pane.searchEntry("switcherRows", L("switcher_rows_title"), keywords: combinedIcon),
            pane.searchEntry("overviewAllAccounts", L("Show all accounts in Overview"), keywords: combinedIcon),
            pane.searchEntry("overviewProviders", L("overview_tab_providers_title"), keywords: combinedIcon),
            pane.searchEntry("surpriseMe", L("surprise_me_title"), keywords: animation, L("surprise_me_subtitle")),
        ]
    }
}
