import InternalUI
import SwiftUI

/// The `MacTextField` well (height, side padding, text size and accent focus ring from the native control
/// ladder) around a native field that `MacTextField` cannot hold yet: a secure entry, or a number edited
/// through a format. Give it `.frame(width: MacSize.settingsField)` in a settings row, like any text field.
///
/// `field` receives the well's focus binding; attach it with `.focused(_:)` so the ring follows the field.
@MainActor
struct SettingsFieldWell<Field: View, Trailing: View>: View {
    private let field: (FocusState<Bool>.Binding) -> Field
    private let trailing: Trailing
    @FocusState private var focused: Bool
    @Environment(\.macControlSize) private var controlSize

    init(
        @ViewBuilder field: @escaping (FocusState<Bool>.Binding) -> Field,
        @ViewBuilder trailing: () -> Trailing)
    {
        self.field = field
        self.trailing = trailing()
    }

    var body: some View {
        let metrics = MacControlMetrics.forSize(self.controlSize)
        HStack(spacing: MacSpace.unit) {
            self.field(self.$focused)
                .textFieldStyle(.plain)
            self.trailing
        }
        // Body text is the field text size from the large size up, which every settings section uses.
        .font(MacTextRole.body.font)
        .padding(.horizontal, metrics.paddingX)
        .frame(height: metrics.height)
        .macWell(radius: metrics.radius)
        .macFocusRing(self.focused, radius: metrics.radius)
    }
}

extension SettingsFieldWell where Trailing == EmptyView {
    init(@ViewBuilder field: @escaping (FocusState<Bool>.Binding) -> Field) {
        self.init(field: field) { EmptyView() }
    }
}

/// A secret entry in the library field well: dots while hidden, plain text while revealed, with an eye
/// button inside the well that switches between them.
@MainActor
struct SettingsSecureField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isRevealed: Bool

    var body: some View {
        SettingsFieldWell { focus in
            if self.isRevealed {
                TextField(self.placeholder, text: self.$text).focused(focus)
            } else {
                SecureField(self.placeholder, text: self.$text).focused(focus)
            }
        } trailing: {
            Button {
                self.isRevealed.toggle()
            } label: {
                Image(systemName: self.isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(MacColor.muted)
            }
            .buttonStyle(.plain)
            .help(self.isRevealed ? L("menu_bar_layout_conditional_hide") : L("http_server_show"))
            .accessibilityLabel(self.isRevealed ? L("menu_bar_layout_conditional_hide") : L("http_server_show"))
        }
    }
}

/// A unit after a value inside a field well, such as "%".
@MainActor
struct SettingsFieldUnit: View {
    let unit: String

    var body: some View {
        Text(verbatim: self.unit)
            .foregroundStyle(MacColor.muted)
            .accessibilityHidden(true)
    }
}
