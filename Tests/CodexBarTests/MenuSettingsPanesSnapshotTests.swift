import CodexBarCore
import Foundation
import InternalUI
import SwiftUI
import Testing
@testable import CodexBar

/// Renders the Menu Bar and Menu panes, the conditionals sheet and the Overview providers picker offscreen, in
/// light and dark, with real-length stress data and every disabled state. Each render must succeed; set
/// TOLKEIN_SNAPSHOT_DIR to also write the PNGs for design review (see Sources/CodexBar/AGENTS.md).
@MainActor
struct MenuSettingsPanesSnapshotTests {
    /// The Settings window's default detail width: the 880 pt window less its 260 pt sidebar.
    private static let paneWidth = SettingsPane.windowWidth - SettingsPane.sidebarWidth
    /// The widest the detail column grows.
    /// The old cap on the detail column; it now fills the window, so this is just a wide case.
    private static let wideWidth: CGFloat = 780
    /// The window's default height, which the panes must scroll in.
    private static let shortHeight = SettingsPane.windowHeight

    private struct Case {
        let name: String
        let width: CGFloat
        let height: CGFloat
        let view: @MainActor () -> AnyView
    }

    @Test func `panes sheet and picker render in every state and appearance`() throws {
        let directory = ProcessInfo.processInfo.environment["TOLKEIN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            var stores: [UsageStore] = []
            defer { stores.forEach { $0.stopSharedSpendDashboardPublication() } }
            @MainActor
            func pane(_ make: (SettingsStore, UsageStore) -> some View, settings: SettingsStore) -> AnyView {
                let store = MenuSettingsPanesFixture.store(settings: settings)
                stores.append(store)
                Self.seedCostStatus(store: store)
                return AnyView(make(settings, store))
            }
            let cases: [Case] = [
                Case(name: "menu-bar-stress", width: Self.paneWidth, height: 3600) {
                    pane({ MenuBarSettingsPane(settings: $0, store: $1) }, settings: Self.menuBarStressSettings())
                },
                Case(name: "menu-bar-stress-wide", width: Self.wideWidth, height: 3300) {
                    pane({ MenuBarSettingsPane(settings: $0, store: $1) }, settings: Self.menuBarStressSettings())
                },
                Case(name: "menu-bar-stress-short", width: Self.paneWidth, height: Self.shortHeight) {
                    pane({ MenuBarSettingsPane(settings: $0, store: $1) }, settings: Self.menuBarStressSettings())
                },
                Case(name: "menu-bar-critters", width: Self.paneWidth, height: 3000) {
                    pane({ MenuBarSettingsPane(settings: $0, store: $1) }, settings: Self.menuBarCrittersSettings())
                },
                Case(name: "menu-bar-merge-off", width: Self.paneWidth, height: 3000) {
                    pane({ MenuBarSettingsPane(settings: $0, store: $1) }, settings: Self.menuBarMergeOffSettings())
                },
                Case(name: "menu-bar-one-provider", width: Self.paneWidth, height: 3000) {
                    pane(
                        { MenuBarSettingsPane(settings: $0, store: $1) },
                        settings: Self.menuBarOneProviderSettings())
                },
                Case(name: "menu-stress", width: Self.paneWidth, height: 2000) {
                    pane({ MenuSettingsPane(settings: $0, store: $1) }, settings: Self.menuStressSettings())
                },
                Case(name: "menu-disabled", width: Self.paneWidth, height: 1700) {
                    pane({ MenuSettingsPane(settings: $0, store: $1) }, settings: Self.menuDisabledSettings())
                },
                Case(name: "menu-remote-off", width: Self.paneWidth, height: 1900) {
                    pane({ MenuSettingsPane(settings: $0, store: $1) }, settings: Self.menuRemoteOffSettings())
                },
                Case(name: "menu-short", width: Self.paneWidth, height: Self.shortHeight) {
                    pane({ MenuSettingsPane(settings: $0, store: $1) }, settings: Self.menuStressSettings())
                },
                Case(name: "conditional-sheet-stress", width: MacSize.settingsContentWidth, height: 760) {
                    AnyView(Self.sheet(Self.stressConditional, existingNames: ["session resets soon"]))
                },
                Case(name: "conditional-sheet-new", width: MacSize.settingsContentWidth, height: 470) {
                    AnyView(Self.sheet(.makeDefault(), existingNames: [], mode: .create))
                },
                Case(
                    name: "overview-picker",
                    width: MacSize.inspectorWidth + MacSpace.settingsPagePadding * 2,
                    height: 420)
                {
                    AnyView(Self.overviewPicker)
                },
            ]
            for appearance in [MacAppearance.light, .dark] {
                for item in cases {
                    let shot = MacSnapshot.render(
                        item.view(),
                        appearance: appearance,
                        width: item.width,
                        height: item.height,
                        background: MacColor.window)
                    let rendered = try #require(shot, "\(item.name) \(appearance.rawValue) did not render")
                    #expect(rendered.size == CGSize(width: item.width, height: item.height))
                    if let directory {
                        try rendered.png.write(to: directory.appending(path: "\(item.name)-\(appearance.rawValue).png"))
                    }
                }
            }
        }
    }

    // MARK: - Menu Bar settings

    /// Enabled providers with the longest display names, so rows, pop-ups and the Overview summary run long.
    private static var longNamedProviders: [UsageProvider] {
        Array(UsageProvider.allCases
            .sorted { Self.name($0).count > Self.name($1).count || Self.name($0).count == Self.name($1).count
                && $0.rawValue < $1.rawValue
            }
            .prefix(9))
    }

    private static func name(_ provider: UsageProvider) -> String {
        ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
    }

    private static let conditionalIDs = [UUID(), UUID(), UUID()]

    private static var stressLayout: MenuBarLayout {
        MenuBarLayout(lines: [
            [
                .icon, .providerName, .accountLabel, .percent(window: .session), .separatorDot,
                .percent(window: .weekly), .pace(window: .weekly), .resetCountdown,
                .windowResetAbsolute(window: .weekly), .conditional(id: conditionalIDs[0]),
            ],
            [
                .progressBar(window: .session), .progressBar(window: .weekly), .runsOut, .costToday,
                .spendBudget, .balance, .tokensSparkline, .separator(.pipe), .space,
                .conditional(id: conditionalIDs[1]),
            ],
        ])
    }

    private static var stressConditionals: [MenuBarLayoutConditional] {
        [
            MenuBarLayoutConditional(
                id: conditionalIDs[0],
                name: "Weekly nearly out, slow down",
                clauses: [MenuBarConditionalClause(
                    combinator: nil,
                    predicate: MenuBarConditionalPredicate(metric: .weekly, comparison: .greaterThan, threshold: 85))],
                thenToken: .pace(window: .weekly),
                elseToken: .hidden),
            MenuBarLayoutConditional(
                id: conditionalIDs[1],
                name: "Spend over the monthly budget",
                clauses: [MenuBarConditionalClause(
                    combinator: nil,
                    predicate: MenuBarConditionalPredicate(
                        metric: .spendAmount, comparison: .greaterThanOrEqual, threshold: 500))],
                thenToken: .spendBudget,
                elseToken: .spendAmount),
            MenuBarLayoutConditional(
                id: conditionalIDs[2],
                name: "Session resets soon",
                clauses: [MenuBarConditionalClause(
                    combinator: nil,
                    predicate: MenuBarConditionalPredicate(
                        metric: .sessionResetsIn, comparison: .lessThan, threshold: 1.5))],
                thenToken: .resetCountdown,
                elseToken: .percent(window: .session)),
        ]
    }

    private static func menuBarStressSettings() -> SettingsStore {
        let providers = Self.longNamedProviders
        let settings = MenuSettingsPanesFixture.settings(suite: "MenuBarSnapshot-stress", enabled: providers)
        settings.menuBarIconStyle = .iconAndPercent
        settings.menuBarLayoutConditionals = Self.stressConditionals
        settings.setMenuBarLayout(Self.stressLayout, for: nil)
        settings.setMenuBarLayout(MenuBarLayout(lines: [[.icon, .percent(window: .weekly)]]), for: providers[1])
        settings.setMenuBarLayout(MenuBarLayout(lines: [[.providerName, .resetCountdown]]), for: providers[3])
        settings.mergeIcons = true
        settings.mergedIconDisplayStyle = .stacked
        settings.mergeIconStackedTopProvider = providers[0]
        settings.menuBarColorPace = true
        settings.mergedOverviewAllAccounts = true
        return settings
    }

    /// Critters: the icon options, the layout and the combined icon style say they need Icon & percent.
    private static func menuBarCrittersSettings() -> SettingsStore {
        let settings = MenuSettingsPanesFixture.settings(
            suite: "MenuBarSnapshot-critters",
            enabled: Array(Self.longNamedProviders.prefix(3)))
        settings.menuBarIconStyle = .critters
        settings.mergeIcons = true
        settings.randomBlinkEnabled = true
        return settings
    }

    /// Merge icons off: every combined icon and Overview row says it needs Merge icons.
    private static func menuBarMergeOffSettings() -> SettingsStore {
        let settings = MenuSettingsPanesFixture.settings(suite: "MenuBarSnapshot-merge-off")
        settings.menuBarIconStyle = .iconAndPercent
        settings.mergeIcons = false
        return settings
    }

    /// One provider: Stacked needs two, and Overview has only one to choose.
    private static func menuBarOneProviderSettings() -> SettingsStore {
        let settings = MenuSettingsPanesFixture.settings(suite: "MenuBarSnapshot-one", enabled: [.claude])
        settings.menuBarIconStyle = .iconAndPercent
        settings.mergeIcons = true
        return settings
    }

    // MARK: - Menu settings

    private static func menuStressSettings() -> SettingsStore {
        let settings = MenuSettingsPanesFixture.settings(suite: "MenuSnapshot-stress")
        settings.weeklyProgressWorkDays = 5
        settings.workdayTickAppearance = .highContrast
        settings.costSummaryOption = .both
        settings.costReportingPeriod = .rolling(days: 45)
        settings.costComparisonPeriodsEnabled = true
        settings.agentSessionsEnabled = true
        settings.agentSessionsRemoteEnabled = true
        settings.agentSessionsManualHosts =
            "developer@build-server.example.internal, ops@staging-gpu-cluster.example.internal"
        settings.accountWidgetsEnabled = true
        return settings
    }

    /// Automatic work days and agent sessions off: the tick style and every session option say why.
    private static func menuDisabledSettings() -> SettingsStore {
        let settings = MenuSettingsPanesFixture.settings(suite: "MenuSnapshot-disabled")
        settings.weeklyProgressWorkDays = nil
        settings.costSummaryOption = .off
        settings.agentSessionsEnabled = false
        return settings
    }

    /// Agent sessions on, remote sessions off: the remote host options say they need remote sessions.
    private static func menuRemoteOffSettings() -> SettingsStore {
        let settings = MenuSettingsPanesFixture.settings(suite: "MenuSnapshot-remote-off")
        settings.costSummaryOption = .inlineSummary
        settings.costReportingPeriod = .monthToDate
        settings.agentSessionsEnabled = true
        settings.agentSessionsRemoteEnabled = false
        return settings
    }

    private static func seedCostStatus(store: UsageStore) {
        store._setTokenErrorForTesting(
            "Local usage scan timed out after 10 minutes while reading ~/.codex/sessions; try again later",
            provider: .codex)
    }

    // MARK: - Sheet and picker

    private static var stressConditional: MenuBarLayoutConditional {
        MenuBarLayoutConditional(
            name: "Weekly nearly out, slow down",
            clauses: [
                MenuBarConditionalClause(
                    combinator: nil,
                    predicate: MenuBarConditionalPredicate(
                        metric: .weekly, direction: .remaining, comparison: .lessThan, threshold: 15)),
                MenuBarConditionalClause(
                    combinator: .and,
                    predicate: MenuBarConditionalPredicate(
                        metric: .weeklyResetsIn, comparison: .greaterThan, threshold: 36.5)),
                MenuBarConditionalClause(
                    combinator: .or,
                    predicate: MenuBarConditionalPredicate(
                        metric: .costWindow, comparison: .greaterThanOrEqual, threshold: 250)),
                MenuBarConditionalClause(
                    combinator: .and,
                    predicate: MenuBarConditionalPredicate(
                        metric: .weeklyPace, comparison: .greaterThan, threshold: -10)),
            ],
            thenToken: .windowResetCountdown(window: .weekly),
            elseToken: .separator(.pipe))
    }

    /// Editing shows a valid, long-named conditional at the four-clause limit (Add Condition off); creating starts
    /// with an empty name, so the error shows and Save is off.
    private static func sheet(
        _ conditional: MenuBarLayoutConditional,
        existingNames: Set<String>,
        mode: MenuBarLayoutConditionalDraft.Mode = .edit(UUID())) -> some View
    {
        MenuBarLayoutConditionalEditorSheet(
            draft: MenuBarLayoutConditionalDraft(mode: mode, conditional: conditional),
            provider: .codex,
            existingNames: existingNames,
            onSave: { _ in })
    }

    private static var overviewPicker: some View {
        let providers = Self.longNamedProviders.map(\.instanceID)
        return MenuBarOverviewProviderPicker(
            providers: providers,
            selected: Array(providers.prefix(MenuBarSettingsPane.maxOverviewProviders)),
            limit: MenuBarSettingsPane.maxOverviewProviders,
            name: { $0.firstPartyProvider.map(Self.name) ?? $0.rawValue },
            setSelection: { _, _ in })
    }
}
