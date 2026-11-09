import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

/// Which quota-warning controls the Alerts pane offers. The Session and Weekly threshold rows appear under
/// Threshold warnings while it is on; the delivery options (sound, on-screen alert) serve both threshold and pace
/// warnings, so they are enabled while either is on.
struct QuotaWarningSettingsVisibility: Equatable {
    let showsThresholdControls: Bool
    let showsDeliveryControls: Bool

    init(thresholdWarningsEnabled: Bool, predictiveWarningsEnabled: Bool) {
        self.showsThresholdControls = thresholdWarningsEnabled
        self.showsDeliveryControls = thresholdWarningsEnabled || predictiveWarningsEnabled
    }
}

/// One window's row under Threshold warnings in the Alerts pane: the window's Warning and Critical fields and
/// the switch that turns its warnings on.
@MainActor
struct GlobalQuotaWarningWindowRow: View {
    let window: QuotaWarningWindow
    @Bindable var settings: SettingsStore

    var body: some View {
        let isEnabled = self.settings.quotaWarningWindowEnabled(self.window)
        IUSettingsRow(self.window.localizedCapitalizedDisplayName) {
            HStack(spacing: IUSpace.settingsRowPaddingX) {
                QuotaWarningThresholdFields(
                    accessibilityContext: self.window.localizedCapitalizedDisplayName,
                    thresholds: { self.settings.quotaWarningThresholds(self.window) },
                    setThresholds: { self.settings.setQuotaWarningThresholds(self.window, thresholds: $0) })
                    .disabled(!isEnabled)

                Toggle(
                    L("quota_warning_enable_warnings", self.window.localizedNotificationDisplayName),
                    isOn: Binding(
                        get: { self.settings.quotaWarningWindowEnabled(self.window) },
                        set: { self.settings.setQuotaWarningWindowEnabled(self.window, enabled: $0) }))
                    .toggleStyle(.iuSwitch)
                    .labelsHidden()
            }
        }
    }
}

/// A provider's own quota warnings, as a section of its Settings page: for each window, Global (inherit the
/// Alerts pane's thresholds), Custom (this provider's own Warning and Critical) or Off.
@MainActor
struct ProviderQuotaWarningSettingsView: View {
    let provider: UsageProvider
    @Bindable var settings: SettingsStore

    var body: some View {
        IUSettingsSection(L("quota_warnings_title"), footer: self.footerText) {
            self.modeRow(.session)
            self.customThresholdRow(.session)
            self.modeRow(.weekly)
            self.customThresholdRow(.weekly)
        }
        .disabled(!self.controlsEnabled)
    }

    var controlsEnabled: Bool {
        self.settings.quotaWarningNotificationsEnabled || self.settings.quotaWarningMarkersVisible
    }

    var footerText: String {
        if self.settings.quotaWarningNotificationsEnabled {
            return L("quota_warning_provider_inherits")
        }
        if self.settings.quotaWarningMarkersVisible {
            return L("quota_warning_provider_markers_only")
        }
        return L("quota_warning_provider_disabled")
    }

    /// The window's row: Global, Custom or Off, with the inherited thresholds as its subtitle while it is Global.
    private func modeRow(_ window: QuotaWarningWindow) -> some View {
        IUSettingsRow(window.localizedCapitalizedDisplayName, subtitle: self.inheritedSummary(for: window)) {
            IUSegmentedControl(
                ProviderQuotaWarningOverrideMode.allCases.map { ($0, $0.title) },
                selection: self.overrideModeBinding(for: window))
        }
    }

    /// The window's own Warning and Critical fields, under its row while it is Custom.
    @ViewBuilder
    private func customThresholdRow(_ window: QuotaWarningWindow) -> some View {
        if self.overrideMode(for: window) == .custom {
            IUSettingsRow(L("quota_warning_window_warn_at", window.localizedCapitalizedDisplayName)) {
                QuotaWarningThresholdFields(
                    accessibilityContext: window.localizedCapitalizedDisplayName,
                    shouldCommitOnDisappear: {
                        self.shouldCommitThresholdEditorOnDisappear(for: window)
                    },
                    thresholds: {
                        self.settings.resolvedQuotaWarningThresholds(provider: self.provider.instanceID, window: window)
                    },
                    setThresholds: {
                        self.settings.setQuotaWarningThresholdsIfOverridden(
                            provider: self.provider,
                            window: window,
                            thresholds: $0)
                    })
            }
        }
    }

    func inheritedSummary(for window: QuotaWarningWindow) -> String? {
        guard self.overrideMode(for: window) == .global else { return nil }
        return L("quota_warning_inherited", Self.thresholdText(
            self.settings.quotaWarningThresholds(window),
            enabled: self.settings.quotaWarningWindowEnabled(window)))
    }

    func overrideModeBinding(for window: QuotaWarningWindow) -> Binding<ProviderQuotaWarningOverrideMode> {
        Binding(
            get: { self.overrideMode(for: window) },
            set: { mode in
                let currentMode = self.overrideMode(for: window)
                guard mode != currentMode else { return }

                switch mode {
                case .custom:
                    self.settings.setQuotaWarningOverride(
                        provider: self.provider,
                        window: window,
                        thresholds: self.settings.explicitQuotaWarningThresholds(
                            provider: self.provider,
                            window: window),
                        enabled: true)
                case .off:
                    self.settings.setQuotaWarningOverride(
                        provider: self.provider,
                        window: window,
                        thresholds: currentMode == .custom
                            ? self.settings.explicitQuotaWarningThresholds(
                                provider: self.provider,
                                window: window)
                            : nil,
                        enabled: false)
                case .global:
                    self.settings.setQuotaWarningOverride(
                        provider: self.provider,
                        window: window,
                        thresholds: nil,
                        enabled: nil)
                }
            })
    }

    func overrideMode(for window: QuotaWarningWindow) -> ProviderQuotaWarningOverrideMode {
        guard self.settings.hasQuotaWarningOverride(provider: self.provider, window: window) else {
            return .global
        }
        return self.settings.quotaWarningEnabled(provider: self.provider, window: window) ? .custom : .off
    }

    func shouldCommitThresholdEditorOnDisappear(for window: QuotaWarningWindow) -> Bool {
        let mode = self.overrideMode(for: window)
        return mode == .custom || mode == .off
    }

    /// The thresholds a window inherits, as the Global subtitle shows them: "Warning 80%, Critical 50%, 20%".
    static func thresholdText(_ thresholds: [Int], enabled: Bool) -> String {
        guard enabled else { return L("quota_warning_off") }
        let activeThresholds = QuotaWarningThresholds.active(thresholds)
        guard let upperThreshold = activeThresholds.first else {
            return L("quota_warning_depleted_only")
        }

        var parts: [String] = []
        parts.append(L("quota_warning_threshold_named", L("quota_warning_warning"), self.percentText(upperThreshold)))
        if let lowerThreshold = activeThresholds.dropFirst().first {
            parts.append(L(
                "quota_warning_threshold_named",
                L("quota_warning_critical"),
                self.percentText(lowerThreshold)))
        }
        parts.append(contentsOf: activeThresholds.dropFirst(2).map(self.percentText))
        return parts.joined(separator: ", ")
    }

    /// A threshold as a localized percentage ("80%", "%80" in Turkish).
    static func percentText(_ value: Int) -> String {
        L("quota_warning_percent_value", value)
    }
}

enum ProviderQuotaWarningOverrideMode: Hashable, CaseIterable {
    case global
    case custom
    case off

    var title: String {
        switch self {
        case .global: L("quota_warning_global")
        case .custom: L("Custom")
        case .off: L("quota_warning_off")
        }
    }
}

struct FocusResigningBackground: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                NSApplication.shared.keyWindow?.makeFirstResponder(nil)
            }
    }
}

extension QuotaWarningWindow {
    var localizedCapitalizedDisplayName: String {
        switch self {
        case .session: L("Session")
        case .weekly: L("quota_warning_weekly_capitalized")
        }
    }
}

/// A window's Warning and Critical thresholds as two short fields ("Warning [50] %  Critical [20] %"). Typing
/// only edits a draft; the thresholds are saved on Return, when focus leaves the fields (a click elsewhere
/// included) and when the fields go away, and only if the text changed.
@MainActor
private struct QuotaWarningThresholdFields: View {
    /// Two digits and the field's own padding: a quarter of a settings text field.
    private static let fieldWidth = IUSize.settingsField / 4

    let accessibilityContext: String
    var shouldCommitOnDisappear: () -> Bool = { true }
    let thresholds: () -> [Int]
    let setThresholds: ([Int]) -> Void

    @State private var draft = QuotaWarningThresholdEditorText.Draft()
    @FocusState private var focusedField: QuotaWarningThresholdEditorText.Field?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: IUSpace.panelPadding) {
            self.input(.upper)
            self.input(.lower)
        }
        .onAppear { self.updateText(from: self.thresholds()) }
        .onChange(of: self.focusedField) { previous, current in
            if previous != nil, current == nil {
                self.commit()
            }
        }
        .onChange(of: self.thresholds()) { _, value in
            if self.focusedField == nil {
                self.updateText(from: value)
            }
        }
        .onDisappear {
            if self.shouldCommitOnDisappear() {
                self.commit()
            }
        }
        .background(self.focusMonitor)
    }

    private func input(_ field: QuotaWarningThresholdEditorText.Field) -> some View {
        let label = field.label
        return HStack(alignment: .firstTextBaseline, spacing: IUSpace.unit) {
            Text(label)
                .font(IUTextRole.body.font)
                .foregroundStyle(IUColor.muted)
                .accessibilityHidden(true)

            IUTextField(field.placeholder, text: self.textBinding(field))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: Self.fieldWidth)
                .focused(self.$focusedField, equals: field)
                .onSubmit {
                    self.commit()
                    self.focusedField = nil
                }
                .accessibilityLabel(Text(self.accessibilityLabel(for: label)))

            Text(L("quota_warning_percent_unit"))
                .font(IUTextRole.body.font)
                .foregroundStyle(IUColor.muted)
                .accessibilityHidden(true)
        }
    }

    private func textBinding(_ field: QuotaWarningThresholdEditorText.Field) -> Binding<String> {
        Binding(
            get: { self.draft.text(for: field) },
            set: { self.draft.setText($0, for: field) })
    }

    private func commit() {
        guard let sanitized = self.draft.takeResolvedThresholds() else { return }
        self.setThresholds(sanitized)
        self.updateText(from: sanitized)
    }

    private func updateText(from thresholds: [Int]) {
        self.draft.update(from: thresholds)
    }

    private func accessibilityLabel(for label: String) -> String {
        guard !self.accessibilityContext.isEmpty else { return label }
        return "\(self.accessibilityContext), \(label)"
    }

    private var focusMonitor: some View {
        QuotaWarningFocusMonitor(isActive: self.focusedField != nil) {
            NSApplication.shared.keyWindow?.makeFirstResponder(nil)
            self.focusedField = nil
        }
    }
}

extension QuotaWarningThresholdEditorText.Field {
    /// The field's label: Warning for the higher threshold, Critical for the lower.
    var label: String {
        switch self {
        case .upper: L("quota_warning_warning")
        case .lower: L("quota_warning_critical")
        }
    }

    /// The default threshold, shown while the field is empty.
    var placeholder: String {
        switch self {
        case .upper: String(QuotaWarningThresholds.defaults[0])
        case .lower: String(QuotaWarningThresholds.defaults[1])
        }
    }
}

private struct QuotaWarningFocusMonitor: NSViewRepresentable {
    let isActive: Bool
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> QuotaWarningFocusMonitorView {
        let view = QuotaWarningFocusMonitorView()
        view.isActive = self.isActive
        view.onOutsideClick = self.onOutsideClick
        return view
    }

    func updateNSView(_ nsView: QuotaWarningFocusMonitorView, context: Context) {
        nsView.isActive = self.isActive
        nsView.onOutsideClick = self.onOutsideClick
    }

    static func dismantleNSView(_ nsView: QuotaWarningFocusMonitorView, coordinator: ()) {
        nsView.invalidate()
    }
}

private final class QuotaWarningFocusMonitorView: NSView {
    var onOutsideClick: (() -> Void)?
    var isActive: Bool = false {
        didSet { self.updateMonitor() }
    }

    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func invalidate() {
        self.isActive = false
        self.onOutsideClick = nil
    }

    private func updateMonitor() {
        if self.isActive {
            self.installMonitor()
        } else {
            self.removeMonitor()
        }
    }

    private func installMonitor() {
        guard self.monitor == nil else { return }
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard self.isActive else { return }
        guard let window = self.window, event.window === window else { return }

        let location = self.convert(event.locationInWindow, from: nil)
        guard !self.bounds.contains(location) else { return }
        guard !Self.eventHitsTextInput(event) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onOutsideClick?()
        }
    }

    private static func eventHitsTextInput(_ event: NSEvent) -> Bool {
        guard let contentView = event.window?.contentView else { return false }
        let location = contentView.convert(event.locationInWindow, from: nil)
        guard let hitView = contentView.hitTest(location) else { return false }
        return hitView.hasAncestor(of: NSTextField.self) || hitView.hasAncestor(of: NSTextView.self)
    }
}

extension NSView {
    fileprivate func hasAncestor<T: NSView>(of type: T.Type) -> Bool {
        var view: NSView? = self
        while let current = view {
            if current is T {
                return true
            }
            view = current.superview
        }
        return false
    }
}

enum QuotaWarningThresholdEditorText {
    enum Field: Hashable {
        case upper
        case lower
    }

    struct Draft {
        private(set) var upperText: String
        private(set) var lowerText: String
        private let initialUpperText: String
        private let initialLowerText: String

        var isDirty: Bool {
            self.upperText != self.initialUpperText || self.lowerText != self.initialLowerText
        }

        init(thresholds: [Int] = QuotaWarningThresholds.defaults) {
            let pair = QuotaWarningThresholdEditorText.displayText(from: thresholds)
            let upperText = pair.upper.map(String.init) ?? ""
            let lowerText = pair.lower.map(String.init) ?? ""
            self.upperText = upperText
            self.lowerText = lowerText
            self.initialUpperText = upperText
            self.initialLowerText = lowerText
        }

        func text(for field: Field) -> String {
            switch field {
            case .upper: self.upperText
            case .lower: self.lowerText
            }
        }

        mutating func setText(_ value: String, for field: Field) {
            let filtered = QuotaWarningThresholdEditorText.filteredIntegerText(value)
            guard self.text(for: field) != filtered else { return }
            switch field {
            case .upper: self.upperText = filtered
            case .lower: self.lowerText = filtered
            }
        }

        mutating func update(from thresholds: [Int]) {
            self = Draft(thresholds: thresholds)
        }

        mutating func takeResolvedThresholds() -> [Int]? {
            guard self.isDirty else { return nil }
            let thresholds = QuotaWarningThresholdEditorText.resolvedThresholds(
                upperText: self.upperText,
                lowerText: self.lowerText)
            self.update(from: thresholds)
            return thresholds
        }
    }

    static func displayText(from thresholds: [Int]) -> (upper: Int?, lower: Int?) {
        let sanitized = QuotaWarningThresholds.sanitized(thresholds)
        return (sanitized.first, sanitized.dropFirst().first)
    }

    static func resolvedThresholds(upperText: String, lowerText: String) -> [Int] {
        QuotaWarningThresholds.resolved(
            upper: self.integer(from: upperText),
            lower: self.integer(from: lowerText))
    }

    static func filteredIntegerText(_ text: String) -> String {
        String(text.filter(\.isNumber).prefix(2))
    }

    private static func integer(from text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        return Int(text)
    }
}
