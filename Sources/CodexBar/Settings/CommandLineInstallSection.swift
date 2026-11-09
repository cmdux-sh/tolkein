import Foundation
import InternalUI
import SwiftUI

/// What one bin directory said when the CLI was installed into it.
struct CLIInstallResult: Equatable, Identifiable {
    enum Outcome: Equatable {
        /// The `codexbar` link points at this app's helper, newly made or already there.
        case installed
        /// Another file already has the name, so it was left alone.
        case exists
        case noWriteAccess
        case failed
    }

    let directory: String
    let outcome: Outcome

    var id: String {
        self.directory
    }

    var label: String {
        switch self.outcome {
        case .installed: L("Installed")
        case .exists: L("A different file exists")
        case .noWriteAccess: L("No write access")
        case .failed: L("Failed")
        }
    }

    var tone: IUStatusTone {
        switch self.outcome {
        case .installed: .neutral
        case .exists, .noWriteAccess: .warning
        case .failed: .error
        }
    }

    var systemImage: String? {
        self.outcome == .installed ? "checkmark.circle.fill" : nil
    }
}

/// The outcome of Install CLI.
enum CLIInstallReport: Equatable {
    /// The app bundle has no CLI helper to link to.
    case helperMissing
    /// Neither bin directory exists.
    case noWritableDirectories
    /// One result per bin directory that exists: installs first, then conflicts, then failures.
    case results([CLIInstallResult])

    static func make(
        installed: [String],
        conflicts: [String],
        failures: [(directory: String, outcome: CLIInstallResult.Outcome)]) -> CLIInstallReport
    {
        let results = installed.map { CLIInstallResult(directory: $0, outcome: .installed) }
            + conflicts.map { CLIInstallResult(directory: $0, outcome: .exists) }
            + failures.map { CLIInstallResult(directory: $0.directory, outcome: $0.outcome) }
        return results.isEmpty ? .noWritableDirectories : .results(results)
    }
}

/// Installs the bundled CLI as `codexbar` in the Homebrew and `/usr/local` bin directories, and links to its help.
@MainActor
struct CommandLineInstallSection: View {
    static let helpURL = URL(string: "https://github.com/cmdux-sh/tolkein/blob/main/docs/cli.md#install")!

    @State private var isInstalling = false
    @State private var report: CLIInstallReport?
    @Environment(\.openURL) private var openURL

    /// - Parameter report: a result to show before any install runs; snapshot tests use it.
    init(report: CLIInstallReport? = nil) {
        self._report = State(initialValue: report)
    }

    var body: some View {
        IUSettingsSection(L("section_command_line")) {
            IUSettingsRow(L("install_cli"), subtitle: L("install_cli_subtitle")) {
                Button {
                    Task { await self.install() }
                } label: {
                    HStack(spacing: IUSpace.unit * 2) {
                        if self.isInstalling {
                            ProgressView().controlSize(.small)
                        }
                        Text(L("install_cli"))
                    }
                }
                .buttonStyle(.iu())
                .disabled(self.isInstalling)
            }
            .settingsAnchor(IntegrationsSettingsPane.anchor(.installCLI))
            self.reportRows
            IUSettingsLinkRow(L("Tolkein Help"), systemImage: "questionmark.circle") {
                self.openURL(Self.helpURL)
            }
        }
    }

    @ViewBuilder
    private var reportRows: some View {
        switch self.report {
        case .none:
            EmptyView()
        case .helperMissing:
            IUSettingsRow(L("Status")) {
                IUStatusLabel(L("cli_not_found"), tone: .error)
            }
        case .noWritableDirectories:
            IUSettingsRow(L("Status")) {
                IUStatusLabel(L("no_writable_bin_dirs"), tone: .warning)
            }
        case let .results(results):
            ForEach(results) { result in
                IUSettingsRow(result.directory) {
                    IUStatusLabel(result.label, tone: result.tone, systemImage: result.systemImage)
                }
                .textSelection(.enabled)
            }
        }
    }
}

extension CommandLineInstallSection {
    private func install() async {
        guard !self.isInstalling else { return }
        self.isInstalling = true
        defer { self.isInstalling = false }
        self.report = Self
            .installCLI(helperURL: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexBarCLI"))
    }

    static func installCLI(
        helperURL: URL,
        destinations: [String] = ["/usr/local/bin/codexbar", "/opt/homebrew/bin/codexbar"],
        fileManager fm: FileManager = .default) -> CLIInstallReport
    {
        guard fm.fileExists(atPath: helperURL.path) else { return .helperMissing }

        var installed: [String] = []
        var conflicts: [String] = []
        var failures: [(directory: String, outcome: CLIInstallResult.Outcome)] = []
        for dest in destinations {
            let dir = (dest as NSString).deletingLastPathComponent
            guard fm.fileExists(atPath: dir) else { continue }

            if fm.fileExists(atPath: dest) {
                if Self.isLink(atPath: dest, pointingTo: helperURL.path, fileManager: fm) {
                    installed.append(dir)
                } else {
                    conflicts.append(dir)
                }
                continue
            }

            guard fm.isWritableFile(atPath: dir) else {
                failures.append((dir, .noWriteAccess))
                continue
            }

            do {
                try fm.createSymbolicLink(atPath: dest, withDestinationPath: helperURL.path)
                installed.append(dir)
            } catch {
                failures.append((dir, .failed))
            }
        }
        return .make(installed: installed, conflicts: conflicts, failures: failures)
    }

    private static func isLink(
        atPath path: String,
        pointingTo destination: String,
        fileManager fm: FileManager) -> Bool
    {
        guard let link = try? fm.destinationOfSymbolicLink(atPath: path) else { return false }
        let dir = (path as NSString).deletingLastPathComponent
        let resolved = URL(fileURLWithPath: link, relativeTo: URL(fileURLWithPath: dir))
            .standardizedFileURL
            .path
        return resolved == destination
    }
}
