import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CommandLineInstallSectionTests {
    @Test
    func `cli install report keeps installs first then conflicts then failures`() {
        let report = CLIInstallReport.make(
            installed: ["/opt/homebrew/bin"],
            conflicts: ["/usr/local/bin"],
            failures: [])

        #expect(report == .results([
            CLIInstallResult(directory: "/opt/homebrew/bin", outcome: .installed),
            CLIInstallResult(directory: "/usr/local/bin", outcome: .exists),
        ]))
    }

    @Test
    func `cli install report shows skipped protected directories alongside successful installs`() {
        let report = CLIInstallReport.make(
            installed: ["/opt/homebrew/bin"],
            conflicts: [],
            failures: [("/usr/local/bin", .noWriteAccess)])

        #expect(report == .results([
            CLIInstallResult(directory: "/opt/homebrew/bin", outcome: .installed),
            CLIInstallResult(directory: "/usr/local/bin", outcome: .noWriteAccess),
        ]))
    }

    @Test
    func `cli install report falls back to the no directories message when nothing exists`() {
        #expect(CLIInstallReport.make(installed: [], conflicts: [], failures: []) == .noWritableDirectories)
    }

    @Test
    func `cli install results are localized with a tone per outcome`() {
        let results: [CLIInstallResult.Outcome: (String, String)] = [
            .installed: (L("Installed"), "neutral"),
            .exists: (L("A different file exists"), "warning"),
            .noWriteAccess: (L("No write access"), "warning"),
            .failed: (L("Failed"), "error"),
        ]
        for (outcome, expected) in results {
            let result = CLIInstallResult(directory: "/usr/local/bin", outcome: outcome)
            #expect(result.label == expected.0)
            #expect(result.tone.rawValue == expected.1)
        }
    }

    @Test
    func `install links into existing bin directories and reports conflicts and missing helpers`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommandLineInstallSectionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("Helpers/CodexBarCLI")
        let free = root.appendingPathComponent("free-bin", isDirectory: true)
        let taken = root.appendingPathComponent("taken-bin", isDirectory: true)
        let absent = root.appendingPathComponent("absent-bin", isDirectory: true)
        for directory in [helper.deletingLastPathComponent(), free, taken] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("#!/bin/sh\n".utf8).write(to: helper)
        try Data("other tool\n".utf8).write(to: taken.appendingPathComponent("codexbar"))
        let destinations = [free, taken, absent].map { $0.appendingPathComponent("codexbar").path }

        let missing = CommandLineInstallSection.installCLI(
            helperURL: root.appendingPathComponent("missing"),
            destinations: destinations)
        #expect(missing == .helperMissing)

        let first = CommandLineInstallSection.installCLI(helperURL: helper, destinations: destinations)
        #expect(first == .results([
            CLIInstallResult(directory: free.path, outcome: .installed),
            CLIInstallResult(directory: taken.path, outcome: .exists),
        ]))
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: destinations[0])
        #expect(link == helper.path)

        // Running it again finds its own link and still calls that directory installed.
        let second = CommandLineInstallSection.installCLI(helperURL: helper, destinations: destinations)
        #expect(second == first)
    }
}
