import AppKit
import CodexBarCore
import InternalUI
import SwiftUI

/// One third-party component and its generated, verbatim notices.
struct Acknowledgement: Equatable, Identifiable {
    private struct Entry: Decodable {
        struct Source: Decodable {
            let text: String
        }

        let name: String
        let authors: [String]
        let url: String
        let license: String
        let sources: [Source]
    }

    let name: String
    let authors: [String]
    let url: String
    let license: String
    let text: String

    var id: String {
        self.name
    }

    /// Up to two authors, then "and N others"; a lone extra author is named rather than counted.
    /// Formats with the app's selected language so the joined list and "others" text never mix languages.
    func authorSummary(locale: Locale = codexBarLocalizedResourceLocale()) -> String {
        let shown = self.authors.count > 3
            ? Array(self.authors.prefix(2)) + [L("acknowledgements_others", self.authors.count - 2)]
            : self.authors
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: shown) ?? shown.joined(separator: ", ")
    }

    static func load(bundle: Bundle? = CodexBarCoreResources.bundle) -> [Acknowledgement] {
        guard let url = bundle?.url(forResource: "Acknowledgements", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.map { entry in
            Acknowledgement(
                name: entry.name,
                authors: entry.authors,
                url: entry.url,
                license: entry.license,
                text: entry.sources.map(\.text).joined(separator: "\n\n"))
        }
    }
}

/// The open-source components Tolkein ships, each a disclosure row that opens to its authors, website and full
/// license text, with the credit to CodexBar under them. Shown as a sheet from About.
@MainActor
struct AcknowledgementsSheet: View {
    let acknowledgements: [Acknowledgement]
    /// Components shown open when the sheet appears (for snapshots); people open the rest themselves.
    var initiallyExpanded: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        IUSettingsPage(L("link_acknowledgements"), subtitle: L("acknowledgements_footer")) {
            Button(L("Done")) { self.dismiss() }
                .buttonStyle(.iu(.primary))
                .iuControlSize(.large)
                .keyboardShortcut(.defaultAction)
        } content: {
            IUSettingsSection {
                ForEach(self.acknowledgements) { acknowledgement in
                    AcknowledgementRow(
                        acknowledgement: acknowledgement,
                        isExpanded: self.initiallyExpanded.contains(acknowledgement.id))
                }
            }
            Text(AboutSettingsPane.creditText())
                .font(IUTextRole.caption.font)
                .foregroundStyle(IUColor.muted)
                .tint(IUColor.accent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(width: IUSize.settingsContentWidth, height: SettingsPane.windowMinHeight)
    }
}

/// One component: its name, authors and license on the closed row; the details and license text when open.
@MainActor
private struct AcknowledgementRow: View {
    let acknowledgement: Acknowledgement
    @State private var isExpanded: Bool

    init(acknowledgement: Acknowledgement, isExpanded: Bool) {
        self.acknowledgement = acknowledgement
        self._isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: self.$isExpanded) {
            VStack(alignment: .leading, spacing: IUSpace.settingsRowPaddingY * 2) {
                self.detail(L(self.acknowledgement.authors.count == 1
                        ? "acknowledgements_author"
                        : "acknowledgements_authors"))
                {
                    Text(self.acknowledgement.authors.joined(separator: "\n"))
                        .font(IUTextRole.body.font)
                        .foregroundStyle(IUColor.primary)
                }
                if let url = URL(string: self.acknowledgement.url) {
                    self.detail(L("Website")) {
                        Link(self.acknowledgement.url, destination: url)
                            .font(IUTextRole.body.font)
                            .tint(IUColor.accent)
                    }
                }
                self.detail(L("acknowledgements_license")) {
                    Text(self.acknowledgement.text)
                        .font(IUTextRole.caption.font)
                        .monospaced()
                        .foregroundStyle(IUColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(IUSpace.panelPadding)
                        .iuWell(radius: IURadius.row)
                        // License text is verbatim English, laid out left to right.
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, IUSpace.settingsRowPaddingY)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: IUSpace.unit * 2) {
                IUText(self.acknowledgement.name)
                    .layoutPriority(1)
                IUText(self.acknowledgement.authorSummary(), role: .caption, muted: true)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: IUSpace.unit * 2)
                IUBadge(self.acknowledgement.license)
            }
            .contentShape(Rectangle())
            .onTapGesture { self.isExpanded.toggle() }
        }
        .iuAnimation(IUSpring.moderate, value: self.isExpanded)
        .padding(.horizontal, IUSpace.settingsRowPaddingX)
        .padding(.vertical, IUSpace.settingsRowPaddingY)
        .frame(maxWidth: .infinity, minHeight: IUSize.settingsRow, alignment: .leading)
    }

    private func detail(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: IUSpace.unit) {
            IUText(title, role: .subtitle)
            content()
        }
    }
}
