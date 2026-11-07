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

    /// Real-length data for design review: long facts and captions, notes that repeat facts, four
    /// provider commands and most providers failing. Render it at a short height to check scrolling.
    @MainActor
    static func stressSession() -> UsageBoardSession {
        let session = UsageBoardSession()
        session.providers = [self.stressClaude] + self.failingProviders
        session.providerCommands = [
            UsageBoardCommand(id: "refresh", title: "Refresh", systemImage: "arrow.clockwise", action: .refresh),
            UsageBoardCommand(
                id: "switch",
                title: "Switch Account...",
                systemImage: "arrow.right.square",
                action: .classicMenu),
            UsageBoardCommand(
                id: "dashboard",
                title: "Usage Dashboard",
                systemImage: "chart.xyaxis.line",
                action: .classicMenu),
            UsageBoardCommand(
                id: "status",
                title: "Status Page",
                systemImage: "waveform.path.ecg",
                action: .classicMenu),
        ]
        return session
    }

    private static var stressClaude: UsageBoardProvider {
        UsageBoardProviderBuilder.make(
            // Provider-specific by design: DEBUG preview fixture that names real providers so previews look realistic.
            id: "claude",
            name: "Claude",
            planText: "Ultra",
            email: "person@example.com",
            subtitle: "Updated 4 mins ago",
            isLoading: false,
            isError: false,
            metrics: [
                UsageBoardMetric(
                    id: "weekly",
                    title: "Weekly",
                    percent: 69,
                    percentText: "31% left",
                    resetText: "Resets in 5h 59m",
                    detailText: "27% in reserve · Lasts until reset",
                    pacePercent: 4,
                    percentLeft: 31,
                    showsBar: true),
                UsageBoardMetric(
                    id: "fable",
                    title: "Fable weekly",
                    percent: 8,
                    percentText: "92% left",
                    resetText: "Resets in 5h 59m",
                    detailText: "88% in reserve · Lasts until reset",
                    pacePercent: 4,
                    percentLeft: 92,
                    showsBar: true),
            ],
            lines: [
                UsageBoardDetailLine(id: "today", label: "Today", value: "$358.18"),
                UsageBoardDetailLine(id: "window", label: "Est. Current window", value: "$580.64"),
                UsageBoardDetailLine(id: "latest", label: "Latest tokens", value: "1B"),
                UsageBoardDetailLine(id: "window-tokens", label: "Est. Current window tokens", value: "1.6B"),
                UsageBoardDetailLine(id: "30d-cost", label: "30d cost", value: "$4,926.79"),
                UsageBoardDetailLine(id: "30d-tokens", label: "30d tokens", value: "15B"),
            ],
            notes: [
                "Limited usage detail",
                "Today: $358.18 · 1B tokens",
                "Last 30 days: $4,926.79 · 15B tokens",
                "Estimated from local Claude logs at API rates; token totals include cache read/write tokens "
                    + "and may differ from Claude Code /status.",
            ])
    }

    private static var failingProviders: [UsageBoardProvider] {
        // Provider-specific by design: DEBUG preview fixture that names real providers so previews look realistic.
        let names = ["Codex", "Cursor", "Droid", "Gemini", "Manus", "ElevenLabs", "Warp", "Claude Platform"]
        return names.map { name in
            UsageBoardProviderBuilder.make(
                id: name.lowercased().replacingOccurrences(of: " ", with: "-"),
                name: name,
                planText: nil,
                email: "",
                subtitle: "The usage request timed out.",
                isLoading: false,
                isError: true,
                metrics: [],
                lines: [],
                notes: [])
        }
    }

    private static var claude: UsageBoardProvider {
        self.provider(
            // Provider-specific by design: DEBUG preview fixture that names real providers so previews look realistic.
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
            // Provider-specific by design: DEBUG preview fixture that names real providers so previews look realistic.
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
            // Provider-specific by design: DEBUG preview fixture that names real providers so previews look realistic.
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
            // Provider-specific by design: DEBUG preview fixture that names real providers so previews look realistic.
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
            // Provider-specific by design: DEBUG preview fixture that names real providers so previews look realistic.
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

    // swiftlint:disable:next function_parameter_count
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
            percentLeft: min(100, max(0, 100 - percent)),
            showsBar: true)
    }
}
#endif
