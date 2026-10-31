import CodexBarCore
import Testing

@Suite
struct UsageBoardLayoutTests {
    @Test
    func `board grows toward the visible screen between a floor and a cap`() {
        #expect(UsageBoardLayout.classicMenuWidth == 310)
        #expect(UsageBoardLayout.minimumWidth == 930)
        #expect(UsageBoardLayout.maximumWidth == 1560)
        #expect(UsageBoardLayout.preferredWidth == 1560)
        #expect(UsageBoardLayout.fittedWidth(1800) == 1560)
        #expect(UsageBoardLayout.fittedWidth(1600) == 1560)
        #expect(UsageBoardLayout.fittedWidth(1200) == 1184)
        #expect(UsageBoardLayout.fittedWidth(800) == 784)
        #expect(UsageBoardLayout.fittedHeight(1200) == 980)
        #expect(UsageBoardLayout.fittedHeight(700) == 684)
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

    @Test
    func `overview glance keeps session and weekly and drops extra lines`() {
        let session = UsageBoardMetric(
            id: "session",
            title: "Session",
            percent: 42,
            percentText: "42% used",
            resetText: "Resets in 2h 14m · Pace 30%",
            detailText: "17% in deficit",
            showsBar: true)
        let extra = UsageBoardMetric(
            id: "extra",
            title: "Extra usage",
            percent: 10,
            percentText: "10% used",
            resetText: "Lasts until reset",
            detailText: "Includes extra usage",
            showsBar: true)
        let credits = UsageBoardMetric(
            id: "credits",
            title: "Credits",
            percent: nil,
            percentText: "$12.40 left",
            resetText: nil,
            detailText: nil,
            showsBar: false)
        let weekly = UsageBoardMetric(
            id: "weekly",
            title: "Weekly",
            percent: 61,
            percentText: "61% left",
            resetText: "Resets Mon 9:00 AM",
            detailText: "Runs out in 26d",
            showsBar: true)
        let glance = UsageBoardLayout.glanceMetrics([session, extra, credits, weekly])
        #expect(glance.map(\.id) == ["session", "weekly"])
        #expect(UsageBoardLayout.shortPercent("42% used") == "42%")
        #expect(UsageBoardLayout.shortPercent("61% left") == "61%")
        #expect(UsageBoardLayout.shortPercent("$12.40 left") == "$12.40 left")
        #expect(UsageBoardLayout.shortReset("Resets in 2h 14m · Pace 30%") == "2h 14m")
        #expect(UsageBoardLayout.shortReset("Resets Mon 9:00 AM") == "Mon 9:00 AM")
        #expect(UsageBoardLayout.shortReset("Lasts until reset") == nil)
        #expect(UsageBoardLayout.shortReset("17% in deficit · Runs out in 2h") == nil)
    }

    @Test
    func `masonry places the next card in the shortest column`() {
        let placements = UsageBoardLayout.masonryPlacements(
            itemHeights: [40, 20, 30, 10],
            columnCount: 2,
            columnWidth: 100,
            spacing: 8)
        #expect(placements.map(\.column) == [0, 1, 1, 0])
        #expect(placements.map(\.x) == [0, 108, 108, 0])
        #expect(placements.map(\.y) == [0, 0, 28, 48])
        #expect(UsageBoardLayout.masonryContentHeight(of: placements) == 58)

        let ties = UsageBoardLayout.masonryPlacements(
            itemHeights: [10, 10, 10],
            columnCount: 2,
            columnWidth: 50,
            spacing: 0)
        #expect(ties.map(\.column) == [0, 1, 0])
        #expect(ties.map(\.y) == [0, 0, 10])
        #expect(UsageBoardLayout.masonryPlacements(
            itemHeights: [],
            columnCount: 3,
            columnWidth: 100,
            spacing: 4).isEmpty)
    }

    @Test
    func `masonry uses the width and adds columns so the overview can fit without scrolling`() {
        #expect(UsageBoardLayout.masonryColumnCount(
            itemCount: 12,
            availableWidth: 1000,
            minimumColumnWidth: 240,
            spacing: 4) == 4)
        #expect(UsageBoardLayout.masonryColumnWidth(
            availableWidth: 1000,
            columnCount: 4,
            spacing: 4) == 247)
        let comfortable = UsageBoardLayout.masonryColumnCountFitting(
            itemHeights: Array(repeating: 72, count: 12),
            availableWidth: 1000,
            availableHeight: 400,
            minimumColumnWidth: 240,
            spacing: 4)
        #expect(comfortable == 4)
        let packed = UsageBoardLayout.masonryPlacements(
            itemHeights: Array(repeating: 72, count: 12),
            columnCount: comfortable,
            columnWidth: 247,
            spacing: 4)
        #expect(UsageBoardLayout.masonryContentHeight(of: packed) <= 400)

        let tight = UsageBoardLayout.masonryColumnCountFitting(
            itemHeights: Array(repeating: 80, count: 40),
            availableWidth: 1000,
            availableHeight: 400,
            minimumColumnWidth: 240,
            spacing: 4)
        #expect(tight == 6)
        let tightWidth = UsageBoardLayout.masonryColumnWidth(
            availableWidth: 1000,
            columnCount: tight,
            spacing: 4)
        #expect(tightWidth >= 160)
    }
}
