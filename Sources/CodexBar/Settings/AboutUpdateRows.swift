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
            MacSettingsRow(L("Checking for updates…")) {
                ProgressView().controlSize(.small)
            }
        case .upToDate:
            MacSettingsRow(L("Tolkein is up to date")) {
                Image(systemName: "checkmark.circle.fill")
                    .font(MacTextRole.body.font)
                    .foregroundStyle(MacColor.positive)
                    .accessibilityHidden(true)
            }
        case let .available(version):
            MacSettingsRow(String(format: L("Tolkein %@ is available"), version)) {
                Button(String(format: L("Update to %@"), version)) { self.updater.installUpdate() }
                    .buttonStyle(.mac(.primary))
                    .accessibilityIdentifier("about-homebrew-install-update")
            }
        case .installing:
            MacSettingsRow(L("Updating with Homebrew…")) {
                ProgressView().controlSize(.small)
            }
        case let .failed(message):
            AboutUpdatesUnavailableView(
                reason: L("Managed by Homebrew") + "\n" + message,
                command: self.updater.manualUpdateCommand)
                .buttonStyle(.macIcon)
        }
    }
}

/// A settings row saying why the app can't update itself, with the command to run instead and a button that copies
/// it. The copy button takes the button style its container sets (About uses `.macIcon`).
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
        VStack(alignment: .leading, spacing: MacSpace.unit * 2) {
            Text(self.reason)
                .font(MacTextRole.body.font)
                .foregroundStyle(MacColor.muted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let command {
                self.commandWell(command)
            }
        }
        .padding(.horizontal, MacSpace.settingsRowPaddingX)
        .padding(.vertical, MacSpace.settingsRowPaddingY)
        .frame(maxWidth: .infinity, minHeight: MacSize.settingsRow, alignment: .leading)
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
        let side = MacControlMetrics.forSize(.large).height
        return HStack(spacing: MacSpace.unit * 2) {
            Text(command)
                .font(MacTextRole.caption.font)
                .monospaced()
                .foregroundStyle(MacColor.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                self.copyAction(command) { self.didCopy = $0 }
            } label: {
                Label(copyTitle, systemImage: self.didCopy ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .font(MacTextRole.body.font)
                    .foregroundStyle(MacColor.primary)
                    .frame(width: side, height: side)
            }
            .help(copyTitle)
            .accessibilityIdentifier("about-copy-update-command")
        }
        // Commands read left to right in every language.
        .environment(\.layoutDirection, .leftToRight)
        .padding(.leading, MacSpace.panelPadding)
        .padding(.trailing, MacSpace.unit)
        .padding(.vertical, MacSpace.unit)
        .macWell(radius: MacRadius.row)
    }

    private static func copyCommand(_ text: String, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        MenuPasteboardCopy.perform(text, writer: { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            completion(pasteboard.setString(text, forType: .string))
        })
    }
}
