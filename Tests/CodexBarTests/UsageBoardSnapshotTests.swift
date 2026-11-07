import CodexBarCore
import Foundation
import MacDesignSystem
import SwiftUI
import Testing
@testable import CodexBar

/// Renders the Usage Board in every state and appearance, with real-length stress data and a height that must
/// scroll. Each render must succeed; set CODEXBAR_SNAPSHOT_DIR to also write the PNGs for design review
/// (see Sources/CodexBar/AGENTS.md).
@MainActor
struct UsageBoardSnapshotTests {
    private struct Case {
        let name: String
        let session: () -> UsageBoardSession
        let selection: String?
        let height: CGFloat
    }

    private static let width = CGFloat(UsageBoardLayout.preferredWidth)
    private static let height = CGFloat(UsageBoardLayout.preferredHeight)

    private static var cases: [Case] {
        [
            Case(name: "preview-all", session: UsageBoardPreviewData.session, selection: nil, height: height),
            Case(name: "preview-claude", session: UsageBoardPreviewData.session, selection: "claude", height: height),
            Case(name: "stress-all", session: UsageBoardPreviewData.stressSession, selection: nil, height: height),
            Case(
                name: "stress-claude",
                session: UsageBoardPreviewData.stressSession,
                selection: "claude",
                height: height),
            Case(
                name: "stress-claude-short",
                session: UsageBoardPreviewData.stressSession,
                selection: "claude",
                height: 300),
            Case(
                name: "stress-failing",
                session: UsageBoardPreviewData.stressSession,
                selection: "codex",
                height: height),
            Case(name: "loading", session: loadingSession, selection: nil, height: height),
            Case(name: "empty", session: UsageBoardSession.init, selection: nil, height: height),
        ]
    }

    private static func loadingSession() -> UsageBoardSession {
        let session = UsageBoardSession()
        session.isShowingSkeleton = true
        session.isRefreshing = true
        return session
    }

    @Test func boardRendersInEveryStateAndAppearance() throws {
        let directory = ProcessInfo.processInfo.environment["CODEXBAR_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for appearance in [MacAppearance.light, .dark] {
            for item in Self.cases {
                let session = item.session()
                session.select(item.selection)
                let shot = MacSnapshot.render(
                    UsageBoardView(session: session),
                    appearance: appearance,
                    width: Self.width,
                    height: item.height,
                    background: nil)
                let rendered = try #require(shot, "\(item.name) \(appearance.rawValue) did not render")
                #expect(rendered.size == CGSize(width: Self.width, height: item.height))
                if let directory {
                    try rendered.png.write(to: directory.appending(path: "\(item.name)-\(appearance.rawValue).png"))
                }
            }
        }
    }

    @Test func notesThatRestateFactsAreDropped() throws {
        let session = UsageBoardPreviewData.stressSession()
        let claude = try #require(session.providers.first { $0.id == "claude" })
        let notes = UsageBoardStatus.distinctNotes(claude)
        #expect(!notes.contains("Today: $358.18 · 1B tokens"))
        #expect(!notes.contains("Last 30 days: $4,926.79 · 15B tokens"))
        #expect(notes.contains("Limited usage detail"))
        #expect(notes.contains { $0.hasPrefix("Estimated from local Claude logs") })
    }

    @Test func figuresAreMoneyAndAmounts() {
        #expect(UsageBoardStatus.figures(in: "Today: $358.18 · 1B tokens") == ["$358.18", "1B"])
        #expect(UsageBoardStatus.figures(in: "Limited usage detail").isEmpty)
    }
}
