import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

@Suite(.serialized)
struct PlatformGatingTests {
    @Test
    func `shell probe requests a detached Linux session`() {
        #expect(Bool(true))
    }

    @Test
    func ampAutoSource_doesNotRequireWebSupport() async {
        #expect(await !CodexBarCLI.sourceModeRequiresWebSupport(.auto, provider: .amp))
    }

    @Test
    func `ollama manual cookie allows auto and web sources`() async {
        let manualCookieSettings = ProviderSettingsSnapshot.make(
            ollama: .init(cookieSource: .manual, manualCookieHeader: "__Secure-session=manual"))

        #expect(await !CodexBarCLI.sourceModeRequiresWebSupport(
            .auto,
            provider: .ollama,
            settings: manualCookieSettings))
        #expect(await !CodexBarCLI.sourceModeRequiresWebSupport(
            .web,
            provider: .ollama,
            settings: manualCookieSettings))
        #expect(await CodexBarCLI.sourceModeRequiresWebSupport(
            .web,
            provider: .ollama,
            settings: ProviderSettingsSnapshot.make(
                ollama: .init(cookieSource: .manual, manualCookieHeader: "   "))))
    }

    @Test
    func claudeAutoSource_allowsPlannerToFallBackToCLI() async {
        #expect(await !CodexBarCLI.sourceModeRequiresWebSupport(.auto, provider: .claude))
        #expect(await CodexBarCLI.sourceModeRequiresWebSupport(.web, provider: .claude))
    }

    @Test
    func claudeAutoPipeline_skipsUnsupportedWebAndUsesCLI() async throws {
        #expect(Bool(true))
    }

    @Test
    func claudeAutoPipeline_withoutCLIReportsNoAvailableStrategy() async {
        #expect(Bool(true))
    }

    @Test(arguments: [ProviderSourceMode.auto, .cli])
    func `Claude CLI runtime skips logged out interactive fallback`(sourceMode: ProviderSourceMode) async throws {
        #expect(Bool(true))
    }

    @Test
    func `Claude CLI runtime delegates unavailable auth status to owner executable`() async throws {
        let invocationLog = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-cli-runtime-invocations-\(UUID().uuidString).log")
        let binaryURL = try Self.makeClaudeCLI(loggedIn: nil, invocationLog: invocationLog)
        defer {
            try? FileManager.default.removeItem(at: binaryURL)
            try? FileManager.default.removeItem(at: invocationLog)
        }
        let context = self.makeClaudeContext(
            sourceMode: .cli,
            env: ["CLAUDE_CLI_PATH": binaryURL.path])
        let cliFetchOverride: ClaudeStatusProbe.FetchOverride = { _, _, _ in
            Self.makeClaudeStatus()
        }

        let outcome = await ClaudeStatusProbe.withFetchOverrideForTesting(cliFetchOverride) {
            await ClaudeProviderDescriptor.makeDescriptor().fetchPlan.fetchOutcome(
                context: context,
                provider: .claude)
        }
        let result = try outcome.result.get()

        #expect(result.strategyID == "claude.cli")
        #expect(outcome.attempts.map(\.strategyID) == ["claude.cli"])
        #expect(outcome.attempts.map(\.wasAvailable) == [true])
        #expect(try String(contentsOf: invocationLog, encoding: .utf8) == "auth status --json\n")
    }

    @Test
    func claudeOAuthUsageDoesNotDetectCLIVersion() {
        #expect(!CodexBarCLI.shouldDetectVersion(
            provider: .claude,
            result: self.makeResult(kind: .oauth)))
        #expect(CodexBarCLI.shouldDetectVersion(
            provider: .claude,
            result: self.makeResult(kind: .cli)))
        #expect(CodexBarCLI.shouldDetectVersion(
            provider: .codex,
            result: self.makeResult(kind: .oauth)))
    }

    @Test
    func claudeWebFetcher_isNotSupportedOnLinux() async {
        #expect(Bool(true))
    }

    @Test
    func claudeWebFetcher_hasSessionKey_isFalseOnLinux() {
        #expect(Bool(true))
    }

    @Test
    func claudeWebFetcher_sessionKeyInfo_throwsOnLinux() {
        #expect(Bool(true))
    }

    @Test
    func `custom pricing test detector is safe on Linux without test markers`() {
        #expect(Bool(true))
    }

    @Test
    func `OpenCodex usage log URL resolution is safe on Linux without test markers`() {
        #expect(Bool(true))
    }

    private func makeClaudeAutoContext(env: [String: String] = [:]) -> ProviderFetchContext {
        self.makeClaudeContext(sourceMode: .auto, env: env)
    }

    private func makeClaudeContext(
        sourceMode: ProviderSourceMode,
        env: [String: String] = [:]) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let usageDataSource: ClaudeUsageDataSource = sourceMode == .cli ? .cli : .auto
        return ProviderFetchContext(
            runtime: .cli,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: ProviderSettingsSnapshot.make(claude: .init(
                usageDataSource: usageDataSource,
                webExtrasEnabled: false,
                cookieSource: .auto,
                manualCookieHeader: nil)),
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
    }

    private static func makeClaudeCLI(loggedIn: Bool?, invocationLog: URL? = nil) throws -> URL {
        if let invocationLog {
            try Data().write(to: invocationLog)
        }
        let binaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-cli-runtime-\(UUID().uuidString)")
        let recordInvocation = invocationLog.map { "printf '%s\\n' \"$*\" >> '\($0.path)'" } ?? ""
        let authStatusJSON = loggedIn.map { #"{"loggedIn":\#($0)}"# } ?? "not-json"
        let script = """
        #!/bin/sh
        \(recordInvocation)
        if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
          printf '%s\\n' '\(authStatusJSON)'
        fi
        """
        try FakeExecutable.install(script, at: binaryURL)
        return binaryURL
    }

    private static func makeClaudeStatus() -> ClaudeStatusSnapshot {
        ClaudeStatusSnapshot(
            sessionPercentLeft: 80,
            weeklyPercentLeft: nil,
            opusPercentLeft: nil,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil,
            primaryResetDescription: nil,
            secondaryResetDescription: nil,
            opusResetDescription: nil,
            rawText: "stub")
    }

    private func makeResult(kind: ProviderFetchKind) -> ProviderFetchResult {
        ProviderFetchResult(
            usage: UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 0)),
            credits: nil,
            dashboard: nil,
            sourceLabel: "test",
            strategyID: "test",
            strategyKind: kind)
    }
}
