import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct IntegrationsSettingsModelTests {
    // MARK: Unapplied HTTP server draft

    @Test
    func `opening with nothing kept starts from the applied configuration without a warning`() {
        let server = StubHTTPServer(configuration: Self.applied)
        let model = IntegrationsSettingsModel(server: server, drafts: HTTPServerDraftStore())

        model.paneAppeared()

        #expect(model.draft == Self.applied)
        #expect(!model.hasUnappliedChanges)
        #expect(model.confirmation == nil)
    }

    @Test
    func `leaving with unapplied edits keeps them and reopening warns`() {
        let server = StubHTTPServer(configuration: Self.applied)
        let drafts = HTTPServerDraftStore()
        let first = IntegrationsSettingsModel(server: server, drafts: drafts)
        first.paneAppeared()
        first.draft.port = 9090
        #expect(first.hasUnappliedChanges)

        first.paneDisappeared()
        #expect(drafts.keptDraft?.port == 9090)

        let reopened = IntegrationsSettingsModel(server: server, drafts: drafts)
        reopened.paneAppeared()
        #expect(reopened.draft.port == 9090)
        #expect(reopened.hasUnappliedChanges)
        #expect(reopened.confirmation == .unappliedHTTPServerChanges)
        #expect(server.appliedConfigurations.isEmpty)
    }

    @Test
    func `leaving without edits keeps nothing and reopening stays quiet`() {
        let server = StubHTTPServer(configuration: Self.applied)
        let drafts = HTTPServerDraftStore()
        let first = IntegrationsSettingsModel(server: server, drafts: drafts)
        first.paneAppeared()
        first.draft.port = 9090
        first.draft.port = Self.applied.port
        first.paneDisappeared()
        #expect(drafts.keptDraft == nil)

        let reopened = IntegrationsSettingsModel(server: server, drafts: drafts)
        reopened.paneAppeared()
        #expect(reopened.confirmation == nil)
    }

    @Test
    func `a kept draft that now matches the applied configuration is dropped`() {
        let drafts = HTTPServerDraftStore()
        var edited = Self.applied
        edited.port = 9090
        drafts.close(draft: edited, applied: Self.applied)

        let opened = drafts.open(applied: edited)

        #expect(opened.draft == edited)
        #expect(!opened.hasUnappliedChanges)
        #expect(drafts.keptDraft == nil)
    }

    @Test
    func `keep editing leaves the draft unapplied and discard restores the applied configuration`() {
        let server = StubHTTPServer(configuration: Self.applied)
        let drafts = HTTPServerDraftStore()
        var edited = Self.applied
        edited.host = "0.0.0.0"
        drafts.close(draft: edited, applied: Self.applied)
        let model = IntegrationsSettingsModel(server: server, drafts: drafts)
        model.paneAppeared()

        model.dismissConfirmation()
        #expect(model.confirmation == nil)
        #expect(model.draft.host == "0.0.0.0")

        model.discardChanges()
        #expect(model.draft == Self.applied)
        #expect(drafts.keptDraft == nil)
        #expect(!model.hasUnappliedChanges)
    }

    @Test
    func `apply saves the draft and clears the unapplied state`() async {
        let server = StubHTTPServer(configuration: Self.applied)
        let model = IntegrationsSettingsModel(server: server, drafts: HTTPServerDraftStore())
        model.paneAppeared()
        model.draft.enabled = true

        await model.apply()

        #expect(server.appliedConfigurations == [model.draft])
        #expect(!model.hasUnappliedChanges)
    }

    @Test
    func `an invalid draft stays unapplied after apply`() async {
        let server = StubHTTPServer(configuration: Self.applied)
        let model = IntegrationsSettingsModel(server: server, drafts: HTTPServerDraftStore())
        model.paneAppeared()
        model.draft.enabled = true
        model.draft.token = ""

        await model.apply()

        #expect(model.hasUnappliedChanges)
        #expect(server.status == model.draft.validationError)
    }

    @Test
    func `a configuration that loads after the pane opened is followed unless the draft has edits`() {
        let server = StubHTTPServer()
        let model = IntegrationsSettingsModel(server: server, drafts: HTTPServerDraftStore())
        model.paneAppeared()

        server.configuration = Self.applied
        model.serverConfigurationChanged()
        #expect(model.draft == Self.applied)
        #expect(!model.hasUnappliedChanges)

        model.draft.port = 9090
        var reloaded = Self.applied
        reloaded.refreshInterval = 120
        server.configuration = reloaded
        model.serverConfigurationChanged()
        #expect(model.draft.port == 9090)
        #expect(model.draft.refreshInterval == Self.applied.refreshInterval)
    }

    @Test
    func `server status shows lifecycle states in the app language and errors by kind`() {
        var invalid = Self.applied
        invalid.token = ""
        let validation = invalid.validationError

        let running = HTTPServerStatusPresentation(status: "Running", validationErrors: [])
        #expect(running.text == L("Running"))
        #expect(running.tone == .neutral)
        #expect(HTTPServerStatusPresentation(status: "Starting…", validationErrors: []).tone == .busy)
        #expect(HTTPServerStatusPresentation(status: "Stopped", validationErrors: []).text == L("Stopped"))

        let warning = HTTPServerStatusPresentation(status: validation ?? "", validationErrors: [validation])
        #expect(warning.tone == .warning)
        let exit = "Server exited (status 1). Check the bind address and port."
        let failure = HTTPServerStatusPresentation(status: exit, validationErrors: [validation])
        #expect(failure.text == exit)
        #expect(failure.tone == .error)
    }

    // MARK: Delete rule confirmation

    @Test
    func `deleting a hook rule waits for confirmation`() {
        let rules = IntegrationsSettingsFixtures.longPathRules
        let settings = IntegrationsSettingsFixtures.settingsStore(suite: "IntegrationsDelete-confirm", hooks: rules)
        let model = IntegrationsSettingsModel(server: StubHTTPServer(), drafts: HTTPServerDraftStore())

        model.requestDelete(rules[1])
        #expect(model.confirmation == .deleteHookRule(id: rules[1].id))
        #expect(settings.hookRules.map(\.id) == rules.map(\.id))

        model.confirmDelete(in: settings)
        #expect(model.confirmation == nil)
        #expect(settings.hookRules.map(\.id) == [rules[0].id, rules[2].id])
    }

    @Test
    func `cancelling a hook rule delete keeps the rule`() {
        let rules = IntegrationsSettingsFixtures.longPathRules
        let settings = IntegrationsSettingsFixtures.settingsStore(suite: "IntegrationsDelete-cancel", hooks: rules)
        let model = IntegrationsSettingsModel(server: StubHTTPServer(), drafts: HTTPServerDraftStore())

        model.requestDelete(rules[0])
        model.dismissConfirmation()
        model.confirmDelete(in: settings)

        #expect(model.confirmation == nil)
        #expect(settings.hookRules.map(\.id) == rules.map(\.id))
    }

    @Test
    func `confirming the unapplied draft warning never deletes a rule`() {
        let rules = IntegrationsSettingsFixtures.longPathRules
        let settings = IntegrationsSettingsFixtures.settingsStore(suite: "IntegrationsDelete-other", hooks: rules)
        let drafts = HTTPServerDraftStore()
        var edited = Self.applied
        edited.port = 9090
        drafts.close(draft: edited, applied: Self.applied)
        let model = IntegrationsSettingsModel(server: StubHTTPServer(configuration: Self.applied), drafts: drafts)
        model.paneAppeared()

        model.confirmDelete(in: settings)

        #expect(model.confirmation == .unappliedHTTPServerChanges)
        #expect(settings.hookRules.count == rules.count)
    }

    private static var applied: HTTPServerConfiguration {
        var configuration = HTTPServerConfiguration()
        configuration.token = "synthetic-token"
        return configuration
    }
}
