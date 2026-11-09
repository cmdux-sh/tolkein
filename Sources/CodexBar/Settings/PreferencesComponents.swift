import SwiftUI

/// Two-line label for grouped-form rows that genuinely need a supporting sentence.
struct SettingsRowLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.title)
                .foregroundStyle(self.isEnabled ? .primary : .secondary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Section footer for grouped forms. macOS renders bare footer text trailing-aligned
/// at body size, which reads badly for long captions; this pins it leading at footnote
/// size in secondary color, matching System Settings captions.
struct SettingsSectionFooter<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        self.content
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsSectionFooter where Content == Text {
    init(_ text: String) {
        self.init { Text(text) }
    }
}
