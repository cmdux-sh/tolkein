import InternalUI
import SwiftUI

extension EnvironmentValues {
    /// The `SettingsSearchEntry.id` that search is jumping to, if any. The settings window sets it when a
    /// search result is chosen; rows marked with `.settingsAnchor(_:)` scroll into view and highlight.
    @Entry var settingsSearchTarget: String?
}

extension View {
    /// Marks a settings row as the destination of a search entry. Pass the entry's id (from the pane's
    /// `searchEntries`): the window scrolls the row into view with a `ScrollViewReader` and tints it
    /// briefly with Internal UI's search highlight.
    func settingsAnchor(_ id: String) -> some View {
        modifier(SettingsAnchorModifier(id: id))
    }
}

private struct SettingsAnchorModifier: ViewModifier {
    let id: String
    @Environment(\.settingsSearchTarget) private var target

    func body(content: Content) -> some View {
        content
            .id(self.id)
            .iuSettingsHighlight(self.target == self.id)
    }
}
