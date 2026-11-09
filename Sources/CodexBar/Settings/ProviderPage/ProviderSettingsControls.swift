import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

// MARK: - Row frame

extension View {
    /// Pads a free-form row (a meter, a list of facts, a note) like a `IUSettingsRow`, so it lines up with the
    /// titled rows in the same `IUSettingsSection`.
    func providerSettingsRow() -> some View {
        self
            .padding(.horizontal, IUSpace.settingsRowPaddingX)
            .padding(.vertical, IUSpace.settingsRowPaddingY)
            .frame(maxWidth: .infinity, minHeight: IUSize.settingsRow, alignment: .leading)
    }
}

/// A muted caption on its own row: a placeholder, a note, or a status line under a setting.
struct ProviderSettingsCaptionRow: View {
    let text: String
    var lineLimit: Int?

    init(_ text: String, lineLimit: Int? = nil) {
        self.text = text
        self.lineLimit = lineLimit
    }

    var body: some View {
        IUText(self.text, role: .caption, muted: true)
            .lineLimit(self.lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .providerSettingsRow()
    }
}

/// Buttons at the trailing edge of their own row.
struct ProviderSettingsTrailingButtonsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: IUSpace.unit * 2) {
            Spacer(minLength: 0)
            self.content
        }
        .providerSettingsRow()
    }
}

// MARK: - Text field

/// A plain or secure text field in the library's field well, the same size as `IUTextField`. Internal UI 0.11 has
/// no secure field and no way to observe a field's focus, which the accent colour needs to commit on focus loss.
struct ProviderTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var isMonospaced = false
    var focus: FocusState<Bool>.Binding?
    @FocusState private var ownFocus: Bool
    @Environment(\.iuControlSize) private var controlSize

    init(
        _ placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        isMonospaced: Bool = false,
        focus: FocusState<Bool>.Binding? = nil)
    {
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.isMonospaced = isMonospaced
        self.focus = focus
    }

    var body: some View {
        let metrics = IUControlMetrics.forSize(self.controlSize)
        let focusBinding = self.focus ?? self.$ownFocus
        Group {
            if self.isSecure {
                SecureField(self.placeholder, text: self.$text)
            } else {
                TextField(self.placeholder, text: self.$text)
            }
        }
        .textFieldStyle(.plain)
        .focused(focusBinding)
        .font(self.isMonospaced ? IUTextRole.body.font.monospaced() : IUTextRole.body.font)
        .padding(.horizontal, metrics.paddingX)
        .frame(height: metrics.height)
        .iuWell(radius: metrics.radius)
        .iuFocusRing(focusBinding.wrappedValue, radius: metrics.radius)
        .accessibilityLabel(self.placeholder)
    }
}

// MARK: - Actions

/// A provider's action buttons, in a row. Bordered actions are standard buttons; link actions are plain ones.
@MainActor
struct ProviderSettingsActionButtons: View {
    let actions: [ProviderSettingsActionDescriptor]

    var visible: [ProviderSettingsActionDescriptor] {
        self.actions.filter { $0.isVisible?() ?? true }
    }

    var body: some View {
        let visible = self.visible
        if !visible.isEmpty {
            HStack(spacing: IUSpace.unit * 2) {
                ForEach(visible) { action in
                    Button(L(action.title)) {
                        Task { @MainActor in
                            await action.perform()
                        }
                    }
                    .buttonStyle(.iu(action.style == .link ? .plain : .standard))
                }
            }
        }
    }
}

/// An actions descriptor as a row: its title and subtitle, and its buttons as the control.
@MainActor
struct ProviderSettingsActionsRow: View {
    let descriptor: ProviderSettingsActionsDescriptor

    var body: some View {
        let subtitle = self.descriptor.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        IUSettingsRow(L(self.descriptor.title), subtitle: subtitle.isEmpty ? nil : L(subtitle)) {
            ProviderSettingsActionButtons(actions: self.descriptor.actions)
        }
    }
}

// MARK: - Picker

/// A picker descriptor as a row: title and (dynamic) subtitle, then any trailing text and actions before the
/// pop-up button.
@MainActor
struct ProviderSettingsPickerRow: View {
    let picker: ProviderSettingsPickerDescriptor

    var body: some View {
        let isEnabled = self.picker.isEnabled?() ?? true
        let subtitle = (self.picker.dynamicSubtitle?() ?? self.picker.subtitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        IUSettingsRow(L(self.picker.title), subtitle: subtitle.isEmpty ? nil : L(subtitle)) {
            HStack(spacing: IUSpace.unit * 2) {
                if let trailingText = self.picker.trailingText?(), !trailingText.isEmpty {
                    IUText(trailingText, role: .caption, muted: true)
                        .lineLimit(1)
                }
                ProviderSettingsActionButtons(actions: self.picker.trailingActions)
                IUPopUpButton(
                    self.picker.options.map { ($0.id, $0.displayTitle) },
                    selection: self.picker.binding)
            }
        }
        .disabled(!isEnabled)
        .onChange(of: self.picker.binding.wrappedValue) { _, selection in
            guard let onChange = self.picker.onChange else { return }
            Task { @MainActor in
                await onChange(selection)
            }
        }
    }
}

// MARK: - Field

/// A text field descriptor as a row: the title on the leading side with the subtitle and footer under it, and the
/// field (with its actions under it) as the control. A field without a title spans the row.
@MainActor
struct ProviderSettingsFieldRow: View {
    let field: ProviderSettingsFieldDescriptor

    private var title: String {
        self.field.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var subtitle: String? {
        let lines = [self.field.subtitle, self.field.footerText ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { L($0) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private var placeholder: String {
        self.field.placeholder.map { $0.isEmpty ? "" : L($0) } ?? ""
    }

    var body: some View {
        if self.title.isEmpty {
            VStack(alignment: .leading, spacing: IUSpace.unit * 2) {
                self.input
                ProviderSettingsActionButtons(actions: self.field.actions)
                if let subtitle {
                    IUText(subtitle, role: .caption, muted: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .providerSettingsRow()
        } else {
            IUSettingsRow(L(self.title), subtitle: self.subtitle) {
                VStack(alignment: .trailing, spacing: IUSpace.unit * 2) {
                    self.input.frame(width: IUSize.settingsField)
                    ProviderSettingsActionButtons(actions: self.field.actions)
                }
            }
        }
    }

    private var input: some View {
        ProviderTextField(self.placeholder, text: self.field.binding, isSecure: self.field.kind == .secure)
    }
}

// MARK: - Toggle

/// A provider toggle and, while it is on, its status line, inline fields and actions as the rows under it.
@MainActor
struct ProviderSettingsToggleRows: View {
    let toggle: ProviderSettingsToggleDescriptor

    var body: some View {
        let isEnabled = self.toggle.isEnabled?() ?? true
        let subtitle = self.toggle.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        IUSettingsToggleRow(
            L(self.toggle.title),
            subtitle: subtitle.isEmpty ? nil : L(subtitle),
            isOn: self.toggle.binding)
            .disabled(!isEnabled)
            .onChange(of: self.toggle.binding.wrappedValue) { _, enabled in
                guard let onChange = self.toggle.onChange else { return }
                Task { @MainActor in
                    await onChange(enabled)
                }
            }
            .task(id: self.toggle.binding.wrappedValue) {
                guard self.toggle.binding.wrappedValue else { return }
                guard let onAppear = self.toggle.onAppearWhenEnabled else { return }
                await onAppear()
            }

        if self.toggle.binding.wrappedValue {
            if let status = self.toggle.statusText?(), !status.isEmpty {
                ProviderSettingsCaptionRow(status, lineLimit: 4)
                    .disabled(!isEnabled)
            }

            ForEach(self.toggle.inlineFields.filter { $0.isVisible?() ?? true }) { field in
                ProviderSettingsFieldRow(field: field)
                    .disabled(!isEnabled)
            }

            let actions = ProviderSettingsActionButtons(actions: self.toggle.actions)
            if !actions.visible.isEmpty {
                ProviderSettingsTrailingButtonsRow { actions }
                    .disabled(!isEnabled)
            }
        }
    }
}

// MARK: - Focus

/// Clicking empty page space ends text editing, so fields that commit on focus loss (the accent colour hex) save.
struct ProviderSettingsFocusResigner: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                NSApplication.shared.keyWindow?.makeFirstResponder(nil)
            }
            .accessibilityHidden(true)
    }
}
