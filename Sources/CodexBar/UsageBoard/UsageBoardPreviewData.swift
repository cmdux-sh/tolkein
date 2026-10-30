import CodexBarCore

#if DEBUG
enum UsageBoardPreviewData {
    @MainActor
    static func session() -> UsageBoardSession {
        let session = UsageBoardSession()
        session.providers = [self.claude, self.codex, self.cursor, self.gemini, self.elevenLabs]
        session.providerCommands = []
        return session
    }

    private static var claude: UsageBoardProvider {
        self.provider(
            id: "claude",
            name: "Claude",
            plan: "Pro",
            email: "person@example.com",
            subtitle: "Updated just now",
            isError: false,
            metrics: [
                self.window(
                    id: "session",
                    title: "Session",
                    percent: 42,
                    reset: "Resets in 2h 14m",
                    detail: "Pace 30%"),
                self.window(id: "weekly", title: "Weekly", percent: 61, reset: "Resets Mon 9:00 AM", detail: nil),
                self.window(id: "credits", title: "Credits", percent: 22, reset: nil, detail: "$12.40 left"),
            ])
    }

    private static var codex: UsageBoardProvider {
        self.provider(
            id: "codex",
            name: "Codex",
            plan: "Plus",
            email: "codex@example.com",
            subtitle: "Updated 4m ago",
            isError: false,
            metrics: [
                self.window(id: "session", title: "Session", percent: 18, reset: "Resets in 3h 02m", detail: nil),
                self.window(id: "weekly", title: "Weekly", percent: 7, reset: "Resets Sun 5:00 PM", detail: nil),
                self.window(id: "opus", title: "Opus", percent: 80, reset: "Resets in 2h 14m", detail: "Model lane"),
            ])
    }

    private static var cursor: UsageBoardProvider {
        UsageBoardProviderBuilder.make(
            id: "cursor",
            name: "Cursor",
            planText: nil,
            email: "",
            subtitle: "Sign in to cursor.com in your browser, then refresh Cursor in CodexBar.",
            isLoading: false,
            isError: true,
            metrics: [],
            lines: [],
            notes: [])
    }

    private static var gemini: UsageBoardProvider {
        UsageBoardProviderBuilder.make(
            id: "gemini",
            name: "Gemini",
            planText: nil,
            email: "",
            subtitle: "The usage request timed out.",
            isLoading: false,
            isError: true,
            metrics: [],
            lines: [],
            notes: [])
    }

    private static var elevenLabs: UsageBoardProvider {
        self.provider(
            id: "elevenlabs",
            name: "ElevenLabs",
            plan: "Creator",
            email: "voice@example.com",
            subtitle: "Updated 1m ago",
            isError: false,
            metrics: [
                self.window(
                    id: "credits",
                    title: "Credits",
                    percent: 96,
                    reset: "Resets in 6d",
                    detail: "1,240 characters left"),
            ])
    }

    private static func provider(
        id: String,
        name: String,
        plan: String,
        email: String,
        subtitle: String,
        isError: Bool,
        metrics: [UsageBoardMetric]) -> UsageBoardProvider
    {
        UsageBoardProviderBuilder.make(
            id: id,
            name: name,
            planText: plan,
            email: email,
            subtitle: subtitle,
            isLoading: false,
            isError: isError,
            metrics: metrics,
            lines: [],
            notes: [])
    }

    private static func window(
        id: String,
        title: String,
        percent: Double,
        reset: String?,
        detail: String?) -> UsageBoardMetric
    {
        UsageBoardMetric(
            id: id,
            title: title,
            percent: percent,
            percentText: "\(Int(percent))% used",
            resetText: reset,
            detailText: detail,
            pacePercent: id == "session" ? 30 : nil,
            showsBar: true)
    }
}
#endif
