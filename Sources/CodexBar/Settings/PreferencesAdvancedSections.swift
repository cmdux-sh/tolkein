import CodexBarCore
import SwiftUI

// The command-line section of the retired Advanced pane. Integrations stacks it with the HTTP server and Hooks;
// Advanced's privacy and diagnostics settings moved to the Privacy & Data pane.

/// Installs the bundled CLI as `codexbar` in the Homebrew and `/usr/local` bin directories.
@MainActor
struct CommandLineInstallSection: View {
    @State private var isInstallingCLI = false
    @State private var cliStatus: String?

    var body: some View {
        Section {
            LabeledContent {
                Button {
                    Task { await self.installCLI() }
                } label: {
                    if self.isInstallingCLI {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L("install_cli"))
                    }
                }
                .disabled(self.isInstallingCLI)
            } label: {
                SettingsRowLabel(L("install_cli"), subtitle: L("install_cli_subtitle"))
            }
        } header: {
            Text(L("section_command_line"))
        } footer: {
            if let status = self.cliStatus {
                SettingsSectionFooter {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(status)
                        Link(L("Tolkein Help"), destination: URL(
                            string: "https://github.com/cmdux-sh/tolkein/blob/main/docs/cli.md#install")!)
                    }
                }
            }
        }
    }
}

extension CommandLineInstallSection {
    private func installCLI() async {
        if self.isInstallingCLI {
            return
        }
        self.isInstallingCLI = true
        defer { self.isInstallingCLI = false }

        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexBarCLI")
        let fm = FileManager.default
        guard fm.fileExists(atPath: helperURL.path) else {
            self.cliStatus = L("cli_not_found")
            return
        }

        let destinations = [
            "/usr/local/bin/codexbar",
            "/opt/homebrew/bin/codexbar",
        ]

        var installed: [String] = []
        var conflicts: [String] = []
        var failures: [String] = []
        for dest in destinations {
            let dir = (dest as NSString).deletingLastPathComponent
            guard fm.fileExists(atPath: dir) else { continue }

            if fm.fileExists(atPath: dest) {
                if Self.isLink(atPath: dest, pointingTo: helperURL.path) {
                    installed.append("Installed: \(dir)")
                } else {
                    conflicts.append("Exists: \(dir)")
                }
                continue
            }

            guard fm.isWritableFile(atPath: dir) else {
                failures.append("No write access: \(dir)")
                continue
            }

            do {
                try fm.createSymbolicLink(atPath: dest, withDestinationPath: helperURL.path)
                installed.append("Installed: \(dir)")
            } catch {
                failures.append("Failed: \(dir)")
            }
        }

        self.cliStatus = Self.cliInstallStatus(
            installed: installed,
            conflicts: conflicts,
            failures: failures)
    }

    private static func isLink(atPath path: String, pointingTo destination: String) -> Bool {
        guard let link = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { return false }
        let dir = (path as NSString).deletingLastPathComponent
        let resolved = URL(fileURLWithPath: link, relativeTo: URL(fileURLWithPath: dir))
            .standardizedFileURL
            .path
        return resolved == destination
    }

    static func cliInstallStatus(installed: [String], conflicts: [String], failures: [String]) -> String {
        let results = installed + conflicts + failures
        return results.isEmpty ? L("no_writable_bin_dirs") : results.joined(separator: " · ")
    }
}
