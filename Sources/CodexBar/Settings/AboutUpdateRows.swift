import AppKit
import InternalUI
import SwiftUI

/// The Homebrew updater's state as rows of About's Updates section: nothing while idle, then checking, up to date,
/// an available version with its Update button, installing, or the failure with the command to run by hand.
@MainActor
struct AboutHomebrewUpdateStatusView: View {
    let updater: HomebrewUpdaterController

    var body: some View {
        switch self.updater.phase {
        case .idle:
            EmptyView()
        case .checking:
            IUSettingsRow(L("Checking for updates…")) {
                ProgressView().controlSize(.small)
            }
        case .upToDate:
            IUSettingsRow(L("Tolkein is up to date")) {
                Image(systemName: "checkmark.circle.fill")
                    .font(IUTextRole.body.font)
                    .foregroundStyle(IUColor.positive)
                    .accessibilityHidden(true)
            }
        case let .available(version):
            IUSettingsRow(String(format: L("Tolkein %@ is available"), version)) {
                Button(String(format: L("Update to %@"), version)) { self.updater.installUpdate() }
                    .buttonStyle(.iu(.primary))
                    .accessibilityIdentifier("about-homebrew-install-update")
            }
        case .installing:
            IUSettingsRow(L("Updating with Homebrew…")) {
                ProgressView().controlSize(.small)
            }
        case let .failed(message):
            AboutUpdatesUnavailableView(
                reason: L("Managed by Homebrew") + "\n" + message,
                command: self.updater.manualUpdateCommand)
                .buttonStyle(.iuIcon)
        }
    }
}

/// A settings row saying why the app can't update itself, with the command to run instead and a button that copies
/// it. The copy button takes the button style its container sets (About uses `.iuIcon`).
@MainActor
struct AboutUpdatesUnavailableView: View {
    typealias CopyAction = @MainActor @Sendable (String, @escaping @MainActor @Sendable (Bool) -> Void) -> Void

    let reason: String
    let command: String?
    let copyAction: CopyAction
    @State private var didCopy = false

    init(
        reason: String,
        command: String? = nil,
        copyAction: @escaping CopyAction = Self.copyCommand)
    {
        self.reason = reason
        self.command = command
        self.copyAction = copyAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IUSpace.unit * 2) {
            Text(self.reason)
                .font(IUTextRole.body.font)
                .foregroundStyle(IUColor.muted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let command {
                self.commandWell(command)
            }
        }
        .padding(.horizontal, IUSpace.settingsRowPaddingX)
        .padding(.vertical, IUSpace.settingsRowPaddingY)
        .frame(maxWidth: .infinity, minHeight: IUSize.settingsRow, alignment: .leading)
        .task(id: self.didCopy) {
            guard self.didCopy else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                self.didCopy = false
            } catch {}
        }
    }

    private func commandWell(_ command: String) -> some View {
        let copyTitle = self.didCopy ? L("Copied") : L("Copy update command")
        let side = IUControlMetrics.forSize(.large).height
        return HStack(spacing: IUSpace.unit * 2) {
            Text(command)
                .font(IUTextRole.caption.font)
                .monospaced()
                .foregroundStyle(IUColor.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                self.copyAction(command) { self.didCopy = $0 }
            } label: {
                Label(copyTitle, systemImage: self.didCopy ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .font(IUTextRole.body.font)
                    .foregroundStyle(IUColor.primary)
                    .frame(width: side, height: side)
            }
            .help(copyTitle)
            .accessibilityIdentifier("about-copy-update-command")
        }
        // Commands read left to right in every language.
        .environment(\.layoutDirection, .leftToRight)
        .padding(.leading, IUSpace.panelPadding)
        .padding(.trailing, IUSpace.unit)
        .padding(.vertical, IUSpace.unit)
        .iuWell(radius: IURadius.row)
    }

    private static func copyCommand(_ text: String, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        MenuPasteboardCopy.perform(text, writer: { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            completion(pasteboard.setString(text, forType: .string))
        })
    }
}
