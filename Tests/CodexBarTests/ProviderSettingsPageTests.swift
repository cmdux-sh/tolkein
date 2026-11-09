import CodexBarCore
import Foundation
import InternalUI
import SwiftUI
import Testing
@testable import CodexBar

/// The provider page's section composition and the token-account remove confirmation.
@MainActor
@Suite(CodexCredentialFixtures(), KeychainOffForProviderPageTests())
struct ProviderSettingsPageTests {
    @Test
    func `a provider with no settings of its own gets only the fixed sections`() {
        let page = Self.makeModel(.vertexai, suite: "ProviderSettingsPageTests-minimal")
        let content = page.pageContent()

        #expect(content.sections == [.status, .usage, .display, .alerts])
        #expect(!content.hasConnectionContent)
        #expect(content.toggles.isEmpty)
    }

    @Test
    func `sections always follow the fixed page order`() {
        for provider in [UsageProvider.claude, .codex, .copilot, .bedrock, .openai, .vertexai] {
            let content = Self.makeModel(provider, suite: "ProviderSettingsPageTests-order-\(provider.rawValue)")
                .pageContent()
            let order = ProviderSettingsPageSection.allCases
            #expect(content.sections == order.filter(content.sections.contains), "\(provider.rawValue)")
            #expect(content.sections.contains(.usage))
            #expect(content.sections.contains(.display))
            #expect(content.sections.contains(.alerts))
        }
    }

    @Test
    func `codex gets its accounts in sign-in and connection`() {
        let page = Self.makeModel(.codex, suite: "ProviderSettingsPageTests-codex")
        page.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "synthetic.person@example.com",
            workspaceAccountID: nil,
            codexHomePath: "/Users/test/.codex",
            observedAt: Date(),
            identity: .emailOnly(normalizedEmail: "synthetic.person@example.com"))
        defer { page.settings._test_liveSystemCodexAccount = nil }
        let content = page.pageContent()

        #expect(content.codexAccounts != nil)
        #expect(content.sections.contains(.connection))
    }

    @Test
    func `openai gets model limits in sign-in and connection and its toggle in options`() {
        let content = Self.makeModel(.openai, suite: "ProviderSettingsPageTests-openai").pageContent()

        #expect(content.modelLimits.map(\.id) == ["openai-org-limits"])
        #expect(content.toggles.map(\.id).contains("openai-live-minutes"))
        #expect(content.sections.contains(.connection))
        #expect(content.sections.contains(.options))
    }

    @Test
    func `claude shows token accounts only with the manual cookie source`() {
        let page = Self.makeModel(.claude, suite: "ProviderSettingsPageTests-claude-accounts")
        page.settings.claudeCookieSource = .auto
        #expect(page.pageContent().tokenAccounts == nil)

        page.settings.claudeCookieSource = .manual
        let content = page.pageContent()
        #expect(content.tokenAccounts != nil)
        #expect(content.sections.contains(.connection))
    }

    @Test
    func `status appears for an error even without facts`() throws {
        let page = Self.makeModel(.vertexai, suite: "ProviderSettingsPageTests-error")
        page.store._setErrorForTesting("Synthetic failure", provider: .vertexai)
        let content = page.pageContent()

        let error = try #require(content.errorDisplay)
        #expect(error.full == "Synthetic failure")
        #expect(content.sections.first == .status)
    }

    @Test
    func `removing a token account asks first and removes it only on confirm`() throws {
        let page = Self.makeModel(.clinepass, suite: "ProviderSettingsPageTests-remove")
        page.settings.addTokenAccount(provider: .clinepass, label: "Personal account", token: "fixture-personal-key")
        page.settings.addTokenAccount(provider: .clinepass, label: "Work", token: "fixture-work-key")
        let descriptor = try #require(page.tokenAccountDescriptor(for: .clinepass))
        let personal = try #require(descriptor.accounts().first)

        page.requestTokenAccountRemoval(personal, descriptor: descriptor)
        let confirmation = try #require(page.activeConfirmation)
        #expect(confirmation.title == L("Remove token account?"))
        #expect(confirmation.message.contains("Personal account"))
        #expect(confirmation.confirmTitle == L("remove"))
        #expect(descriptor.accounts().count == 2)

        page.dismissActiveConfirmation()
        #expect(page.activeConfirmation == nil)
        #expect(descriptor.accounts().count == 2)

        page.requestTokenAccountRemoval(personal, descriptor: descriptor)
        page.confirmActiveConfirmation()
        #expect(page.activeConfirmation == nil)
        #expect(descriptor.accounts().map(\.label) == ["Work"])
    }

    static func makeModel(_ provider: UsageProvider, suite: String) -> ProviderSettingsPageModel {
        let settings = testSettingsStore(
            suiteName: suite,
            userDefaults: InMemoryUserDefaults(),
            tokenAccountStore: InMemoryTokenAccountStore())
        Self.isolateCodexAccounts(settings)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        // Removing or adding an account refreshes the provider; tests never reach a provider's API.
        store._test_providerRefreshOverride = { _ in }
        return ProviderSettingsPageModel(provider: provider, settings: settings, store: store)
    }

    /// Codex's account list reads the managed-account store and CODEX_HOME; point both into the fixture root.
    static func isolateCodexAccounts(_ settings: SettingsStore) {
        let root = CodexCredentialFixtures.root
        settings._test_managedCodexAccountStoreURL = root.appendingPathComponent("managed-codex-accounts.json")
        settings._test_codexReconciliationEnvironment = [
            "CODEX_HOME": root.appendingPathComponent("codex-home", isDirectory: true).path,
        ]
    }
}

/// Keeps Keychain access off for every provider page test, as the snapshot test does, so building a page's
/// content can never reach a Keychain prompt.
struct KeychainOffForProviderPageTests: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool {
        true
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void) async throws
    {
        try await KeychainAccessGate.withTaskOverrideForTesting(true) {
            try await function()
        }
    }
}
