import CodexBarCore
import InternalUI
import SwiftUI

/// Hooks on the Integrations page: the switch, Add rule, and one card per rule (or an empty state).
/// Deleting a rule goes through `requestDelete`, so the page can ask for confirmation first.
@MainActor
struct HooksSections: View {
    @Bindable var settings: SettingsStore
    let requestDelete: (HookRule) -> Void

    var body: some View {
        IUSettingsSection(L("tab_hooks"), footer: L("hooks_trust_warning")) {
            IUSettingsToggleRow(
                L("hooks_enable_title"),
                subtitle: L("hooks_enable_subtitle"),
                isOn: self.enabledBinding)
                .settingsAnchor(IntegrationsSettingsPane.anchor(.hooks))
            IUSettingsRow(
                L("hooks_rules_header"),
                disabledReason: L("At most %d rules.", HooksConfig.maximumRuleCount))
            {
                Button {
                    self.settings.addHookRule(HookRule(event: .quotaReached, executable: ""))
                } label: {
                    Label(L("hooks_add_rule"), systemImage: "plus")
                }
                .buttonStyle(.iu())
            }
            .disabled(!HookEditorValidation.canAddRule(count: self.settings.hookRules.count))
            .settingsAnchor(IntegrationsSettingsPane.anchor(.hookRules))
        }

        if self.settings.hookRules.isEmpty {
            IUSettingsSection {
                IUEmptyState(
                    L("hooks_empty"),
                    systemImage: "terminal",
                    message: L("Add a rule to run a command when a quota or provider event happens."),
                    size: .compact)
            }
        } else {
            ForEach(Array(self.settings.hookRules.enumerated()), id: \.element.id) { index, rule in
                HookRuleCard(
                    number: index + 1,
                    rule: self.binding(for: rule),
                    onDelete: { self.requestDelete(rule) })
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { self.settings.hooksEnabled },
            set: { self.settings.setHooksEnabled($0) })
    }

    private func binding(for rule: HookRule) -> Binding<HookRule> {
        Binding(
            get: { self.settings.hookRules.first(where: { $0.id == rule.id }) ?? rule },
            set: { self.settings.updateHookRule($0) })
    }
}

/// One hook rule as a settings card: on or off, the event and provider it watches, the threshold for
/// quota-low, the command and its arguments, and Delete.
@MainActor
struct HookRuleCard: View {
    let number: Int
    @Binding var rule: HookRule
    let onDelete: () -> Void
    @State private var argumentRows: [ArgumentRow]

    init(number: Int, rule: Binding<HookRule>, onDelete: @escaping () -> Void) {
        self.number = number
        self._rule = rule
        self.onDelete = onDelete
        self._argumentRows = State(initialValue: rule.wrappedValue.arguments.map(ArgumentRow.init(value:)))
    }

    var body: some View {
        IUSettingsSection(L("Rule %d", self.number)) {
            IUSettingsToggleRow(L("hooks_rule_enabled"), isOn: self.$rule.enabled)
            IUSettingsRow(L("hooks_event")) {
                IUPopUpButton(HookEventType.allCases.map { ($0, $0.rawValue) }, selection: self.$rule.event)
            }
            IUSettingsRow(L("hooks_provider")) {
                IUPopUpButton(Self.providerOptions, selection: self.providerBinding)
            }
            if self.rule.event == .quotaLow {
                IUSettingsRow(L("hooks_threshold")) {
                    SettingsFieldWell { focus in
                        TextField(
                            L("hooks_threshold"),
                            value: self.thresholdPercentBinding,
                            format: .number,
                            prompt: Text(L("hooks_threshold_placeholder")))
                            .focused(focus)
                    } trailing: {
                        SettingsFieldUnit(unit: "%")
                    }
                    .frame(width: IUSize.settingsField)
                }
            }
            IUSettingsRow(L("hooks_executable")) {
                IUTextField(L("hooks_executable_placeholder"), text: self.$rule.executable)
                    .frame(width: IUSize.settingsField)
                    .help(self.rule.executable)
            }
            IUSettingsRow(
                L("hooks_arguments_placeholder"),
                disabledReason: L("At most %d arguments.", HookRule.maximumArgumentCount))
            {
                Button {
                    self.argumentRows.append(ArgumentRow(value: ""))
                } label: {
                    Label(L("hooks_add_argument"), systemImage: "plus")
                }
                .buttonStyle(.iu())
            }
            .disabled(!HookEditorValidation.canAddArgument(count: self.argumentRows.count))
            ForEach(Array(self.argumentRows.enumerated()), id: \.element.id) { index, argument in
                IUSettingsRow(L("Argument %d", index + 1)) {
                    HStack(spacing: IUSpace.unit * 2) {
                        Button {
                            self.argumentRows.removeAll(where: { $0.id == argument.id })
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(IUColor.muted)
                        }
                        .buttonStyle(.iuIcon)
                        .help(L("hooks_delete_argument"))
                        .accessibilityLabel(L("hooks_delete_argument"))
                        IUTextField(L("hooks_argument_placeholder"), text: self.argumentBinding(argument.id))
                            .frame(width: IUSize.settingsField)
                            .help(argument.value)
                    }
                }
            }
            IUSettingsRow(L("hooks_delete_rule")) {
                Button(L("Delete…"), action: self.onDelete)
                    .buttonStyle(.iu())
            }
        }
        .onChange(of: self.argumentRows.map(\.value)) { _, arguments in
            if self.rule.arguments != arguments {
                self.rule.arguments = arguments
            }
        }
        .onChange(of: self.rule.arguments) { _, arguments in
            if self.argumentRows.map(\.value) != arguments {
                self.argumentRows = arguments.map(ArgumentRow.init(value:))
            }
        }
    }

    /// Any provider, then every built-in provider, then the installed plugins.
    private static var providerOptions: [(String?, String)] {
        [(nil, L("hooks_any_provider"))]
            + UsageProvider.allCases.map { provider in
                (provider.rawValue, ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName)
            }
            + UserProviderPluginRegistry.all.map { plugin in
                (plugin.manifest.id.rawValue, plugin.manifest.name)
            }
    }

    private var providerBinding: Binding<String?> {
        Binding(get: { self.rule.provider }, set: { self.rule.provider = $0 })
    }

    /// Threshold stored as a 0...1 fraction, edited as a 0...100 percentage.
    private var thresholdPercentBinding: Binding<Double?> {
        Binding(
            get: { self.rule.threshold.map { $0 * 100 } },
            set: { self.rule.threshold = HookEditorValidation.thresholdFraction(percent: $0) })
    }

    private func argumentBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { self.argumentRows.first(where: { $0.id == id })?.value ?? "" },
            set: { value in
                if let index = self.argumentRows.firstIndex(where: { $0.id == id }) {
                    self.argumentRows[index].value = value
                }
            })
    }

    private struct ArgumentRow: Identifiable {
        let id = UUID()
        var value: String
    }
}

enum HookEditorValidation {
    static func canAddRule(count: Int) -> Bool {
        count < HooksConfig.maximumRuleCount
    }

    static func canAddArgument(count: Int) -> Bool {
        count < HookRule.maximumArgumentCount
    }

    static func thresholdFraction(percent: Double?) -> Double? {
        percent.map { min(max($0, 1), 100) / 100 }
    }
}
