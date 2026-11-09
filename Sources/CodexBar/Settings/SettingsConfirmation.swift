import InternalUI
import SwiftUI

/// A question a settings pane asks before an action that can't be undone, or a message it must show (an
/// import that failed). The pane shows it as a `IUAlert` over a scrim with `.settingsConfirmation(_:)`.
struct SettingsConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let systemImage: String
    /// The primary button. It runs `action`, then closes the alert.
    let confirmTitle: String
    /// The secondary button that closes the alert without acting; nil shows only the primary button.
    let cancelTitle: String?
    let action: @MainActor () -> Void

    init(
        title: String,
        message: String,
        systemImage: String = "exclamationmark.triangle.fill",
        confirmTitle: String,
        cancelTitle: String? = L("Cancel"),
        action: @escaping @MainActor () -> Void)
    {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.action = action
    }

    /// A message with a single OK button, for a failure the person needs to read.
    static func notice(title: String, message: String) -> SettingsConfirmation {
        SettingsConfirmation(
            title: title,
            message: message,
            systemImage: "xmark.octagon.fill",
            confirmTitle: L("OK"),
            cancelTitle: nil,
            action: {})
    }
}

extension View {
    /// Shows `confirmation` as an alert over this view while it is set. The view underneath is dimmed and can't be
    /// used until the alert closes; Return picks the primary button and Escape the secondary one.
    func settingsConfirmation(_ confirmation: Binding<SettingsConfirmation?>) -> some View {
        modifier(SettingsConfirmationModifier(confirmation: confirmation))
    }
}

private struct SettingsConfirmationModifier: ViewModifier {
    @Binding var confirmation: SettingsConfirmation?

    func body(content: Content) -> some View {
        content
            .disabled(self.confirmation != nil)
            .accessibilityHidden(self.confirmation != nil)
            .overlay {
                if let confirmation {
                    ZStack {
                        IUColor.scrim
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {}
                            .accessibilityHidden(true)
                        IUAlert(
                            confirmation.title,
                            message: confirmation.message,
                            systemImage: confirmation.systemImage,
                            primary: (confirmation.confirmTitle, {
                                self.confirmation = nil
                                confirmation.action()
                            }),
                            secondary: confirmation.cancelTitle.map { title in
                                (title, { self.confirmation = nil })
                            })
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                }
            }
            .iuAnimation(IUSpring.moderate, value: self.confirmation?.id)
    }
}
