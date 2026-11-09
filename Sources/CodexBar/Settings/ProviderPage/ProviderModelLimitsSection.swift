import CodexBarCore
import InternalUI
import SwiftUI

struct ProviderModelLimitDraft: Identifiable, Equatable {
    let id = UUID()
    var model = ""
    var tpm = ""
    var rpm = ""

    init(limit: ProviderModelRateLimit? = nil) {
        if let limit {
            self.model = limit.model
            self.tpm = ProviderRateLimitNumber.format(limit.tokensPerMinute)
            self.rpm = limit.requestsPerMinute.map(ProviderRateLimitNumber.format) ?? ""
        }
    }

    var value: ProviderModelRateLimit? {
        let name = self.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let rpm = self.rpm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let tpm = ProviderRateLimitNumber.parse(self.tpm),
              rpm.isEmpty || ProviderRateLimitNumber.parse(rpm) != nil else { return nil }
        return .init(model: name, tokensPerMinute: tpm, requestsPerMinute: ProviderRateLimitNumber.parse(rpm))
    }
}

/// Per-model throughput limits: one row per model (name, tokens and requests per minute, remove), Add model, and
/// the provider's actions. Edits stay local until every row is valid, so the saved limits survive typing.
@MainActor
struct ProviderModelLimitsSection: View {
    /// The width of the two number columns: half a settings field each.
    private static let numberColumnWidth = MacSize.settingsField / 2

    let descriptor: ProviderSettingsModelLimitsDescriptor
    @State private var rows: [ProviderModelLimitDraft]

    init(descriptor: ProviderSettingsModelLimitsDescriptor) {
        self.descriptor = descriptor
        self._rows = State(initialValue: descriptor.binding.wrappedValue.map { .init(limit: $0) })
    }

    private var footer: String {
        [L(self.descriptor.subtitle), self.descriptor.scopeText]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var body: some View {
        MacSettingsSection(L(self.descriptor.title), footer: self.footer) {
            if !self.rows.isEmpty {
                HStack(spacing: MacSpace.unit * 2) {
                    MacText(L("Model"), role: .caption, muted: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    MacText("TPM", role: .caption, muted: true)
                        .frame(width: Self.numberColumnWidth, alignment: .leading)
                    MacText(L("RPM (optional)"), role: .caption, muted: true)
                        .frame(width: Self.numberColumnWidth, alignment: .leading)
                    Color.clear.frame(width: MacSize.iconTile, height: MacSize.border)
                }
                .lineLimit(1)
                .padding(.horizontal, MacSpace.settingsRowPaddingX)
                .padding(.top, MacSpace.settingsRowPaddingY)
                .accessibilityHidden(true)
            }
            ForEach(self.$rows) { $row in
                VStack(alignment: .leading, spacing: MacSpace.unit) {
                    HStack(spacing: MacSpace.unit * 2) {
                        ProviderTextField(L("Model"), text: $row.model)
                        ProviderTextField(L("Tokens per minute"), text: $row.tpm)
                            .frame(width: Self.numberColumnWidth)
                        ProviderTextField(L("RPM (optional)"), text: $row.rpm)
                            .frame(width: Self.numberColumnWidth)
                        Button {
                            self.rows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(MacColor.muted)
                                .frame(width: MacSize.iconTile, height: MacSize.iconTile)
                        }
                        .buttonStyle(.macIcon)
                        .accessibilityLabel(L("Remove"))
                    }
                    if row.value == nil {
                        MacText(
                            L("Enter a model and positive limits, such as 40M TPM and 15k RPM."),
                            role: .caption,
                            muted: true)
                    }
                }
                .providerSettingsRow()
            }
            HStack(spacing: MacSpace.unit * 2) {
                ProviderSettingsActionButtons(actions: self.descriptor.actions)
                Spacer(minLength: 0)
                Button(L("Add model")) { self.rows.append(.init()) }
                    .buttonStyle(.mac())
            }
            .providerSettingsRow()
        }
        .onChange(of: self.rows) { _, rows in
            // Keep edits local until every row is valid, preserving the last saved limits while typing.
            let values = rows.compactMap(\.value)
            guard values.count == rows.count else { return }
            self.descriptor.binding.wrappedValue = values
        }
        .onChange(of: self.descriptor.binding.wrappedValue) { _, limits in
            guard ProviderModelRateLimit.validated(self.rows.compactMap(\.value)) != limits else { return }
            self.rows = limits.map { .init(limit: $0) }
        }
    }
}
