import CodexBarCore
import Testing

@Suite
struct UsageBoardLayoutTests {
    @Test
    func `board is three times the classic menu column`() {
        #expect(UsageBoardLayout.classicMenuWidth == 310)
        #expect(UsageBoardLayout.preferredWidth == 930)
        #expect(UsageBoardLayout.fittedWidth(1600) == 930)
        #expect(UsageBoardLayout.fittedWidth(800) == 784)
    }

    @Test
    func `metric columns use the detail width`() {
        #expect(UsageBoardLayout.metricColumnCount(detailWidth: 680, itemCount: 4) == 3)
        #expect(UsageBoardLayout.metricColumnCount(detailWidth: 680, itemCount: 2) == 2)
        #expect(UsageBoardLayout.metricColumnCount(detailWidth: 480, itemCount: 4) == 2)
        #expect(UsageBoardLayout.metricColumnCount(detailWidth: 320, itemCount: 4) == 1)
        #expect(UsageBoardLayout.metricColumnCount(detailWidth: 900, itemCount: 1) == 1)
    }

    @Test
    func `sign-in copy is distinct from a generic error`() {
        #expect(
            UsageBoardLayout.attention(
                isLoading: false,
                isError: true,
                subtitle: "Sign in to chatgpt.com, then refresh.",
                hasContent: false) == .needsSignIn)
        #expect(
            UsageBoardLayout.attention(
                isLoading: false,
                isError: true,
                subtitle: "The usage request timed out.",
                hasContent: false) == .error)
        #expect(
            UsageBoardLayout.attention(
                isLoading: true,
                isError: false,
                subtitle: "Refreshing",
                hasContent: false) == .loading)
        #expect(
            UsageBoardLayout.attention(
                isLoading: true,
                isError: false,
                subtitle: "Refreshing",
                hasContent: true) == .ready)
        #expect(UsageBoardLayout.mentionsSignIn("Logged in via API key") == false)
        #expect(UsageBoardLayout.mentionsSignIn("Re-login at claude.ai") == true)
    }

    @Test
    func `provider board keeps every window and drops exact duplicates`() {
        let session = UsageBoardMetric(
            id: "session",
            title: "Session",
            percent: 42,
            percentText: "42% used",
            resetText: "Resets in 2h 14m",
            detailText: "Pace 30%",
            showsBar: true)
        let weekly = UsageBoardMetric(
            id: "weekly",
            title: "Weekly",
            percent: 61,
            percentText: "61% used",
            resetText: "Resets Mon 9:00 AM",
            detailText: nil,
            showsBar: true)
        let provider = UsageBoardProviderBuilder.make(
            id: "claude",
            name: "Claude",
            planText: "Pro",
            email: "person@example.com",
            subtitle: "Updated just now",
            isLoading: false,
            isError: false,
            metrics: [session, weekly],
            lines: [
                UsageBoardDetailLine(id: "dup", label: "Session", value: "42% used"),
                UsageBoardDetailLine(id: "extra", label: "Session", value: "Includes extra usage"),
                UsageBoardDetailLine(id: "credits", label: "Credits", value: "$12.40 left"),
            ],
            notes: ["  ", "Source: claude.ai"])

        #expect(provider.attention == .ready)
        #expect(provider.monogram == "CL")
        #expect(provider.headlinePercentText == "42% used")
        #expect(provider.headlineCaption == "Session · Resets in 2h 14m")
        #expect(provider.metrics.map(\.id) == ["session", "weekly"])
        #expect(provider.lines.map(\.id) == ["extra", "credits"])
        #expect(provider.notes == ["Source: claude.ai"])
        #expect(provider.metrics[0].accessibilitySummary.contains("Resets in 2h 14m"))
    }

    @Test
    func `monogram uses the first letters of a multiword name`() {
        #expect(UsageBoardLayout.monogram(for: "Claude Platform") == "CP")
        #expect(UsageBoardLayout.monogram(for: "ElevenLabs") == "EL")
    }
}
