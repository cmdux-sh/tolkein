import Foundation
import Testing
@testable import CodexBarCore

struct ManusPluginTests {
    // A saved session token is used first and alone: browser cookies are never opened while one exists,
    // because reading them triggers macOS privacy prompts (docs/decisions.md, 2026-11-06).
    @Test(arguments: BundledPluginTestSupport.engines, [ProviderCookieSource.auto, .manual, .off])
    func `saved session token is used without opening browser cookies`(
        engine: ProviderPluginEngineKind,
        cookieSource: ProviderCookieSource) async throws
    {
        let sessions = SessionQueue([])
        let runtime = try BundledPluginTestSupport.runtime(
            "manus",
            engine: engine,
            transport:
            ProviderHTTPTransportHandler { request in
                let token = request.value(forHTTPHeaderField: "Authorization")
                await sessions.record(token ?? "missing")
                return try CookiePluginFixtures.response(request, body: #"{"totalCredits":5}"#)
            })
        let usage = try await runtime.fetchUsage(
            secrets: ["SESSION_TOKEN": "environment"],
            cookieSource: cookieSource,
            cookieSessionResolver: { _, _ in
                Issue.record("A saved token must not open browser sessions")
                return nil
            },
            cookieResolver: { _, _ in
                Issue.record("A saved token must not import cookies")
                return "session_id=browser"
            })
        #expect(usage.identity?.loginMethod == "Balance: 5 credits")
        #expect(await sessions.attempts == ["Bearer environment"])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `rejected saved token fails without browser fallback`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try BundledPluginTestSupport.runtime(
            "manus",
            engine: engine,
            transport:
            ProviderHTTPTransportHandler { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer environment")
                return try CookiePluginFixtures.response(request, body: "expired", status: 401)
            })
        await CookiePluginFixtures.expectFailure(.authenticationExpired) {
            try await runtime.fetchUsage(
                secrets: ["SESSION_TOKEN": "environment"],
                cookieSessionResolver: { _, _ in
                    Issue.record("A rejected saved token must not fall back to browser cookies")
                    return nil
                })
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `rejected browser sessions are invalidated and fail as expired`(
        engine: ProviderPluginEngineKind) async throws
    {
        let rejected = LockIsolated<[String]>([])
        let sessions = SessionQueue(["session_id=cached", "session_id=browser"])
        let runtime = try BundledPluginTestSupport.runtime(
            "manus",
            engine: engine,
            transport:
            ProviderHTTPTransportHandler { request in
                await sessions.record(request.value(forHTTPHeaderField: "Authorization") ?? "missing")
                return try CookiePluginFixtures.response(request, body: "expired", status: 401)
            })
        await CookiePluginFixtures.expectFailure(.authenticationExpired) {
            try await runtime.fetchUsage(
                cookieSessionResolver: { _, _ in await sessions.next() },
                cookieSessionInvalidator: { domain, id in
                    #expect(domain == "manus.im")
                    rejected.setValue(rejected.value + [id])
                })
        }
        #expect(rejected.value.count == 2)
        #expect(await sessions.attempts == ["Bearer cached", "Bearer browser"])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `manual cookie is used when no token is saved`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try BundledPluginTestSupport.runtime(
            "manus",
            engine: engine,
            transport:
            ProviderHTTPTransportHandler { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer manual")
                return try CookiePluginFixtures.response(request, body: "expired", status: 403)
            })
        await CookiePluginFixtures.expectFailure(.authenticationExpired) {
            try await runtime.fetchUsage(
                cookieSource: .manual,
                cookieResolver: { _, _ in "manual" })
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `off mode without a token never imports cookies or sends a request`(
        engine: ProviderPluginEngineKind) async throws
    {
        let runtime = try BundledPluginTestSupport.runtime(
            "manus",
            engine: engine,
            transport:
            ProviderHTTPTransportHandler { _ in
                Issue.record("Disabled provider must not send a request")
                throw URLError(.badURL)
            })
        await CookiePluginFixtures.expectFailure(.missingCredential) {
            try await runtime.fetchUsage(
                cookieSource: .off,
                cookieResolver: { _, _ in
                    Issue.record("Disabled provider must not import cookies")
                    return "session_id=browser"
                })
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `sparse credits and numeric dates retain native projection`(engine: ProviderPluginEngineKind) async throws {
        let body = #"""
        {"totalCredits":"1200","periodicCredits":"300","proMonthlyCredits":1000,
         "refreshCredits":"bad","maxRefreshCredits":100,"nextRefreshTime":0,"refreshInterval":"DAILY REFRESH"}
        """#
        let runtime = try BundledPluginTestSupport.runtime(
            "manus",
            engine: engine,
            transport:
            ProviderHTTPTransportHandler { request in
                #expect(request.httpMethod == "POST")
                #expect(request.httpBody == Data("{}".utf8))
                return try CookiePluginFixtures.response(request, body: body)
            })
        let usage = try await runtime.fetchUsage(cookieResolver: { _, _ in "Session_ID = fixture" })
        #expect(usage.primary?.usedPercent == 70)
        #expect(usage.primary?.resetDescription == "Total 1,200 • Free 0")
        #expect(usage.secondary?.usedPercent == 100)
        #expect(usage.secondary?.resetsAt == Date(timeIntervalSinceReferenceDate: 0))
        #expect(usage.secondary?.resetDescription == "Daily Refresh: 0 / 100")
    }

    private actor SessionQueue {
        var headers: [String]
        var attempts: [String] = []

        init(_ headers: [String]) { self.headers = headers }

        func next() -> ProviderPluginCookieSession? {
            guard !self.headers.isEmpty else { return nil }
            return .init(header: self.headers.removeFirst(), source: "fixture", origin: "https://manus.im")
        }

        func record(_ token: String) { self.attempts.append(token) }
    }
}
