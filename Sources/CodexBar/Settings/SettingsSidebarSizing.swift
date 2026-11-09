import SwiftUI

extension SettingsPane {
    /// The sidebar column's width bounds, in points. The user's width is saved under `sidebarWidthDefaultsKey`.
    static let sidebarWidth: CGFloat = 260
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarMaxWidth: CGFloat = 380
    static let sidebarWidthDefaultsKey = "settingsSidebarWidth"
}

/// Saves the sidebar width the user drags the native divider to, and restores it as the column's ideal width.
///
/// It saves the width of the sidebar's content. On macOS 26 the split view's sidebar item is a little wider than
/// that (the floating sidebar's inset), so restoring the content width puts the divider back where it was.
struct SettingsSidebarSizing: ViewModifier {
    @Binding var width: Double

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { newWidth in
                // Ignore transient zero/undersized measurements while the split view is being attached.
                guard newWidth >= SettingsPane.sidebarMinWidth,
                      newWidth <= SettingsPane.sidebarMaxWidth,
                      abs(self.width - newWidth) > 0.5 else { return }
                self.width = newWidth
            }
            // Keep this last so the column preference reaches NavigationSplitView.
            .navigationSplitViewColumnWidth(
                min: SettingsPane.sidebarMinWidth,
                ideal: min(max(self.width, SettingsPane.sidebarMinWidth), SettingsPane.sidebarMaxWidth),
                max: SettingsPane.sidebarMaxWidth)
    }
}
