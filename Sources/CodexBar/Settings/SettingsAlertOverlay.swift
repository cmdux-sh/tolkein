import InternalUI
import SwiftUI

extension View {
    /// Shows a `IUAlert` over this settings page while `isPresented` is true: centred on a scrim that dims
    /// the page and takes its clicks, with the page hidden from VoiceOver and keyboard focus until the alert
    /// closes. Return and Escape reach the alert's buttons through their keyboard shortcuts.
    func settingsAlertOverlay(isPresented: Bool, @ViewBuilder alert: () -> some View) -> some View {
        modifier(SettingsAlertOverlay(isPresented: isPresented, alert: alert()))
    }
}

private struct SettingsAlertOverlay<Alert: View>: ViewModifier {
    let isPresented: Bool
    let alert: Alert

    func body(content: Content) -> some View {
        content
            .disabled(self.isPresented)
            .accessibilityHidden(self.isPresented)
            .overlay {
                if self.isPresented {
                    ZStack {
                        IUColor.scrim
                            .contentShape(Rectangle())
                            .onTapGesture {}
                            .accessibilityHidden(true)
                        // IUAlert fills the height it is offered; keep it at its own height.
                        self.alert.fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
    }
}
