import InternalUI
import SwiftUI

enum UnifiedIconSource: String, CaseIterable, Sendable {
    case currentSelection
    case highestUsage
    case frontmostApp

    var label: String {
        switch self {
        case .currentSelection: L("merged_icon_source_current_selection")
        case .highestUsage: L("merged_icon_source_highest_usage")
        case .frontmostApp: L("merged_icon_source_frontmost_app")
        }
    }
}

/// The combined icon's source as a settings row: which provider the single merged icon follows.
struct UnifiedIconSourcePicker: View {
    @Binding var selection: UnifiedIconSource
    /// Shown while the row is disabled, saying why.
    var disabledReason: String?

    var body: some View {
        MacSettingsRow(
            L("merged_icon_source_title"),
            subtitle: L("merged_icon_source_subtitle"),
            disabledReason: self.disabledReason)
        {
            MacPopUpButton(
                MenuBarSettingsMenuOptions.unifiedIconSources.map { ($0, $0.label) },
                selection: self.$selection)
                .accessibilityLabel(L("merged_icon_source_title"))
        }
    }
}
