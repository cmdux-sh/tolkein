import InternalUI
import SwiftUI

/// Draggable chip used by the layout editor for both placed tokens and palette entries.
///
/// Deliberately not a `Button`: on macOS the button's own gesture recognizer claims the mouse-down
/// and the attached `.draggable` never starts a drag session, so neither reordering nor the trash
/// drop zone worked by mouse — the only way to remove a token was the Delete key. Moving
/// `.draggable` onto the button's label does not help, because the button still owns the gesture. A
/// plain view with an explicit tap gesture keeps clicking, dragging, and keyboard activation all
/// working.
struct MenuBarLayoutEditorChip: View {
    let title: String
    let systemImage: String
    let kind: MenuBarLayoutChipLabel.Kind
    let isSelected: Bool
    let isDisabled: Bool
    let accessibilityLabel: String
    let accessibilityHint: String?
    let dragItem: MenuBarLayoutDragItem
    let activate: () -> Void
    var removeActionTitle: String?
    var remove: (() -> Void)?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.iuControlSize) private var controlSize
    @FocusState private var isFocused: Bool

    init(
        title: String,
        systemImage: String,
        kind: MenuBarLayoutChipLabel.Kind = .palette,
        isSelected: Bool = false,
        isDisabled: Bool = false,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        dragItem: MenuBarLayoutDragItem,
        activate: @escaping () -> Void,
        removeActionTitle: String? = nil,
        remove: (() -> Void)? = nil)
    {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.dragItem = dragItem
        self.activate = activate
        self.removeActionTitle = removeActionTitle
        self.remove = remove
    }

    private var isActive: Bool {
        self.isEnabled && !self.isDisabled
    }

    var body: some View {
        MenuBarLayoutChipLabel(
            title: self.title,
            systemImage: self.systemImage,
            isSelected: self.isSelected,
            kind: self.kind)
            .opacity(self.isActive ? 1 : 0.5)
            .contentShape(Capsule(style: .continuous))
            .draggable(self.dragItem)
            .onTapGesture(perform: self.handleActivate)
            .focusable(self.isActive)
            .focused(self.$isFocused)
            .focusEffectDisabled()
            .iuFocusRing(self.isFocused, radius: MenuBarLayoutChipLabel.radius(in: self.controlSize))
            .onKeyPress(keys: [.space, .return], phases: [.down]) { _ in
                guard self.isActive else { return .ignored }
                self.handleActivate()
                return .handled
            }
            .allowsHitTesting(self.isActive)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(self.isSelected ? .isSelected : [])
            .accessibilityLabel(self.accessibilityLabel)
            .accessibilityHint(self.accessibilityHint ?? "")
            .accessibilityAction { self.handleActivate() }
            .modifier(OptionalRemoveAccessibilityAction(
                title: self.removeActionTitle,
                remove: self.remove))
    }

    private func handleActivate() {
        guard self.isActive else { return }
        self.activate()
    }
}

/// A layout token drawn as an Internal UI chip, one step down the control ladder from the section's controls
/// (24 pt beside 28 pt pop-ups), like `IUFilterChips`. Palette entries sit on the raised control fill; placed
/// tokens take the token-field look (accent text on the soft accent); the selected placed token is solid accent.
struct MenuBarLayoutChipLabel: View {
    enum Kind {
        case palette
        case placed
    }

    let title: String
    let systemImage: String
    let isSelected: Bool
    var kind: Kind = .palette

    @Environment(\.iuControlSize) private var controlSize
    @Environment(\.colorSchemeContrast) private var contrast

    /// The chip's control size for the surrounding control size, as filter chips step down.
    static func chipSize(for size: ControlSize) -> ControlSize {
        switch size {
        case .extraLarge: .large
        case .large: .regular
        case .regular: .small
        default: .mini
        }
    }

    static func metrics(in size: ControlSize) -> IUControlMetrics {
        IUControlMetrics.forSize(self.chipSize(for: size))
    }

    static func radius(in size: ControlSize) -> CGFloat {
        self.metrics(in: size).radius
    }

    var body: some View {
        let metrics = Self.metrics(in: self.controlSize)
        let shape = RoundedRectangle(cornerRadius: metrics.radius, style: .circular)
        HStack(spacing: IUSpace.unit) {
            Image(systemName: self.systemImage)
                .font(IUTextRole.caption.font.weight(.semibold))
                .accessibilityHidden(true)
            Text(self.title)
                .font(metrics.font)
                .lineLimit(1)
        }
        .foregroundStyle(self.foreground)
        .padding(.horizontal, metrics.paddingX)
        .frame(height: metrics.height)
        .background {
            switch (self.kind, self.isSelected) {
            case (_, true):
                Color.clear.background(IUColor.accent, in: shape)
            case (.placed, false):
                Color.clear.background(IUColor.accentSoft, in: shape)
                    // Increase Contrast: an accent edge, so a placed token doesn't rest on a soft fill alone.
                        .overlay(shape.strokeBorder(IUColor.accent, lineWidth: IUSize.border)
                            .opacity(self.contrast == .increased ? 1 : 0))
            case (.palette, false):
                Color.clear.iuSurface(radius: metrics.radius, fill: IUColor.raised, elevation: .raised)
            }
        }
        .fixedSize()
    }

    private var foreground: Color {
        if self.isSelected { return IUColor.onAccent }
        return self.kind == .placed ? IUColor.accent : IUColor.primary
    }
}

/// One line of the menu-bar strip: a control well holding the placed tokens, wrapping when they run out of
/// width, that takes drops at its end. The well's corners are concentric with the chips inside it.
struct MenuBarLayoutLineWell<Content: View>: View {
    let isEmpty: Bool
    let accessibilityLabel: String
    let onDrop: (MenuBarLayoutDragItem?) -> Bool
    @ViewBuilder let content: Content

    @Environment(\.iuControlSize) private var controlSize
    @State private var isTargeted = false

    var body: some View {
        let chip = MenuBarLayoutChipLabel.metrics(in: self.controlSize)
        let inset = IUSpace.unit
        let radius = chip.radius + inset
        MenuBarLayoutChipFlowLayout(spacing: IUSpace.chipGap) {
            self.content
            if self.isEmpty {
                Text(L("menu_bar_layout_empty_line"))
                    .font(IUTextRole.caption.font)
                    .foregroundStyle(IUColor.muted)
                    .padding(.horizontal, chip.paddingX)
                    .frame(height: chip.height)
            }
        }
        .padding(inset)
        .frame(maxWidth: .infinity, minHeight: chip.height + inset * 2, alignment: .leading)
        .iuWell(radius: radius)
        .iuFocusRing(self.isTargeted, radius: radius)
        .dropDestination(for: MenuBarLayoutDragItem.self) { items, _ in
            self.onDrop(items.first)
        } isTargeted: { self.isTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(self.accessibilityLabel)
    }
}

/// Trash zone. Accepts drops and doubles as a plain click target so a selected token can be removed without
/// dragging or reaching for the Delete key. It turns destructive while a placed token is selected.
struct MenuBarLayoutRemoveZone: View {
    let canRemoveSelection: Bool
    let removeSelection: () -> Void
    let onDrop: (MenuBarLayoutDragItem?) -> Bool

    @State private var isTargeted = false
    @Environment(\.iuControlSize) private var controlSize

    var body: some View {
        let radius = IUControlMetrics.forSize(self.controlSize).radius
        Button(action: self.removeSelection) {
            Label(
                self.canRemoveSelection ? L("menu_bar_layout_remove_selected") : L("menu_bar_layout_drag_remove"),
                systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.iu(self.canRemoveSelection ? .destructive : .standard))
        .iuFocusRing(self.isTargeted, radius: radius)
        .dropDestination(for: MenuBarLayoutDragItem.self) { items, _ in
            self.onDrop(items.first)
        } isTargeted: { self.isTargeted = $0 }
        .accessibilityLabel(L("menu_bar_layout_drag_remove"))
    }
}

/// Adds the named "Remove" accessibility action only for chips that support removal.
private struct OptionalRemoveAccessibilityAction: ViewModifier {
    let title: String?
    let remove: (() -> Void)?

    func body(content: Content) -> some View {
        if let title, let remove {
            content.accessibilityAction(named: title, remove)
        } else {
            content
        }
    }
}

extension View {
    /// The padding and width of a settings row, for rows of the layout editor that are not a title and a
    /// control (the strip, the palettes), so they line up with the `IUSettingsRow`s around them.
    func menuBarLayoutRowFrame() -> some View {
        self
            .padding(.horizontal, IUSpace.settingsRowPaddingX)
            .padding(.vertical, IUSpace.settingsRowPaddingY)
            .frame(maxWidth: .infinity, minHeight: IUSize.settingsRow, alignment: .leading)
    }
}
