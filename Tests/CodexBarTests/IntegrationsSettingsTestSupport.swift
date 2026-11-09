import CodexBarCore
import Foundation
import Observation
@testable import CodexBar

/// An HTTP server that starts nothing: `apply` validates and stores the configuration like the real
/// controller, and tests set the status and URL they want to show.
@MainActor
@Observable
final class StubHTTPServer: HTTPServerControlling {
    var configuration: HTTPServerConfiguration
    var status = "Stopped"
    var isTransitioning = false
    var runningURL: String?
    private(set) var appliedConfigurations: [HTTPServerConfiguration] = []

    init(configuration: HTTPServerConfiguration = HTTPServerConfiguration()) {
        self.configuration = configuration
    }

    func apply(_ configuration: HTTPServerConfiguration) async {
        self.appliedConfigurations.append(configuration)
        if configuration.enabled, let error = configuration.validationError {
            self.status = error
            return
        }
        self.configuration = configuration
        self.status = configuration.enabled ? "Running" : "Stopped"
        self.runningURL = configuration.enabled ? configuration.url : nil
    }
}

@MainActor
enum IntegrationsSettingsFixtures {
    static func settingsStore(suite: String, hooks: [HookRule] = [], hooksEnabled: Bool = false) -> SettingsStore {
        testSettingsStore(
            suiteName: suite,
            userDefaults: InMemoryUserDefaults(),
            config: CodexBarConfig(providers: [], hooks: HooksConfig(enabled: hooksEnabled, events: hooks)))
    }

    static func usageStore(settings: SettingsStore, approvals: ProviderPluginApprovalStore? = nil) -> UsageStore {
        let approvals = approvals ?? ProviderPluginApprovalStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("IntegrationsSettings-approvals-\(UUID().uuidString).json"))
        return UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            pluginApprovalStore: approvals)
    }

    /// Three rules with real-length paths and arguments, one of them quota-low with a threshold.
    static var longPathRules: [HookRule] {
        [
            HookRule(
                id: "fixture-quota-low",
                enabled: true,
                event: .quotaLow,
                provider: "codex",
                threshold: 0.9,
                executable: "/Users/fixture/Library/Application Support/Tolkein/hooks/notify-when-quota-is-low.sh",
                arguments: ["--channel", "#engineering-usage-alerts-and-quota-warnings"]),
            HookRule(
                id: "fixture-provider-down",
                enabled: false,
                event: .providerUnavailable,
                executable: "/opt/homebrew/Cellar/terminal-notifier/2.0.0/bin/terminal-notifier",
                arguments: ["-title", "Provider unavailable", "-message", "Check the status page before retrying"]),
            HookRule(
                id: "fixture-usage-updated",
                enabled: true,
                event: .usageUpdated,
                provider: "claude",
                executable: "/usr/local/bin/push-usage-to-the-team-dashboard-with-a-very-long-name"),
        ]
    }
}
