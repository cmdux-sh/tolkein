import AppKit
import CodexBarCore
import Foundation
import InternalUI
import SwiftUI
import Testing
@testable import CodexBar

/// The rules behind the rebuilt Menu Bar and Menu panes: disabled reasons, pop-up options, the cost footer, and
/// the search entries that the rows anchor to.
@MainActor
struct MenuSettingsPanesTests {
    @Test
    func `combined icon style says why it is off in the order stacking checks`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(MenuBarSettingsPane.mergedIconStyleDisabledReason(
                mergeIcons: false, iconStyle: .critters, eligibleProviderCount: 0) == "Turn on Merge icons first")
            #expect(MenuBarSettingsPane.mergedIconStyleDisabledReason(
                mergeIcons: true, iconStyle: .bars, eligibleProviderCount: 3) == "Requires the Icon & percent style")
            #expect(MenuBarSettingsPane.mergedIconStyleDisabledReason(
                mergeIcons: true, iconStyle: .iconAndPercent, eligibleProviderCount: 1)
                == "Needs at least two enabled providers")
            #expect(MenuBarSettingsPane.mergedIconStyleDisabledReason(
                mergeIcons: true, iconStyle: .iconAndPercent, eligibleProviderCount: 2) == nil)
        }
    }

    @Test
    func `combined icon style reason is nil exactly when stacking is possible`() {
        for mergeIcons in [false, true] {
            for style in MenuBarIconStyle.allCases {
                for count in 0...3 {
                    let presentation = MergedIconPresentation(
                        mergeIcons: mergeIcons,
                        iconStyle: style,
                        requestedStyle: .stacked,
                        eligibleProviders: Array([UsageProvider.codex, .claude, .cursor].prefix(count)),
                        preferredTop: nil,
                        preferredBottom: nil)
                    let reason = MenuBarSettingsPane.mergedIconStyleDisabledReason(
                        mergeIcons: mergeIcons, iconStyle: style, eligibleProviderCount: count)
                    #expect((reason == nil) == presentation.canStack, "\(mergeIcons) \(style) \(count)")
                }
            }
        }
    }

    @Test
    func `icon source reason covers merge icons and the stacked style`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(MenuBarSettingsPane.iconSourceDisabledReason(mergeIcons: false, effectiveStyle: .stacked)
                == "Turn on Merge icons first")
            #expect(MenuBarSettingsPane.iconSourceDisabledReason(mergeIcons: true, effectiveStyle: .stacked)
                == "Not used by the Stacked style, which picks its top and bottom rows")
            #expect(MenuBarSettingsPane.iconSourceDisabledReason(mergeIcons: true, effectiveStyle: .switcher) == nil)
        }
    }

    @Test
    func `style reasons name the styles they need`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(MenuBarSettingsPane.requiresIconAndPercentReason == "Requires the Icon & percent style")
            #expect(MenuBarSettingsPane.brandIconsReason
                == "Brand icons don't animate. Use the Critters or Meter bars style.")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("de") {
            #expect(MenuBarSettingsPane.requiresIconAndPercentReason.contains(MenuBarIconStyle.iconAndPercent.label))
            #expect(MenuBarSettingsPane.brandIconsReason.contains(MenuBarIconStyle.critters.label))
            #expect(!MenuBarSettingsPane.brandIconsReason.contains("%"))
        }
    }

    @Test
    func `overview providers subtitle lists the choice or explains why there is none`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(MenuBarSettingsPane.overviewProviderSubtitle(
                mergeIcons: false, hasProviders: true, selectedNames: ["Codex"]) == nil)
            #expect(MenuBarSettingsPane.overviewProviderSubtitle(
                mergeIcons: true, hasProviders: false, selectedNames: []) == L("overview_no_providers_hint"))
            #expect(MenuBarSettingsPane.overviewProviderSubtitle(
                mergeIcons: true, hasProviders: true, selectedNames: []) == L("overview_no_providers_selected"))
            #expect(MenuBarSettingsPane.overviewProviderSubtitle(
                mergeIcons: true, hasProviders: true, selectedNames: ["Codex", "Claude"]) == "Codex, Claude")
        }
    }

    @Test
    func `remote host settings need agent sessions and then remote sessions`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(AgentSessionsSettingsSection.remoteHostsDisabledReason(
                agentSessionsEnabled: false, remoteEnabled: true) == "Turn on Agent sessions first")
            #expect(AgentSessionsSettingsSection.remoteHostsDisabledReason(
                agentSessionsEnabled: true, remoteEnabled: false)
                == "Turn on Remote sessions (Tailscale / SSH) first")
            #expect(AgentSessionsSettingsSection.remoteHostsDisabledReason(
                agentSessionsEnabled: true, remoteEnabled: true) == nil)
        }
    }

    @Test
    func `pop up options keep an off list selection visible after the usual choices`() {
        let workDays = MenuSettingsMenuOptions.weeklyProgressWorkDays
        let label = MenuSettingsMenuOptions.weeklyProgressWorkDaysLabel
        #expect(MenuSettingsPopUpOptions.options(workDays, selection: 5, label: label).map(\.0) == workDays)
        #expect(MenuSettingsPopUpOptions.options(workDays, selection: nil, label: label).map(\.0) == workDays)
        let imported = MenuSettingsPopUpOptions.options(workDays, selection: 3, label: label)
        #expect(imported.map(\.0) == [nil, 4, 5, 6, 7, 3])
        #expect(imported.last?.1 == L("%d days", 3))
    }

    @Test
    func `history window lists presets and keeps a custom rolling window`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let presets = CostHistoryDaysEditor.periodOptions(selection: .rolling(days: 30))
            #expect(presets.map(\.0) == [.monthToDate, .allTime] + [1, 7, 30, 90, 365].map { .rolling(days: $0) })
            #expect(presets[0].1 == "Month to date")
            #expect(presets[1].1 == "All")
            #expect(presets[4].1 == CostHistoryDaysEditor.title(days: 30))

            let custom = CostHistoryDaysEditor.periodOptions(selection: .rolling(days: 45))
            #expect(custom.count == presets.count + 1)
            #expect(custom.last?.0 == .rolling(days: 45))
            #expect(custom.last?.1 == CostHistoryDaysEditor.title(days: 45))
        }
    }

    @Test
    func `cost footer frames the provider lines with the refresh note and the explanation`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let footer = CostSummarySettingsSection.footer(statusLines: ["Claude: no data yet", "Codex: no data yet"])
            #expect(footer.components(separatedBy: "\n") == [
                L("cost_auto_refresh_info"),
                "Claude: no data yet",
                "Codex: no data yet",
                CostSummarySettingsSection.costDataExplanation(),
            ])
        }
    }

    @Test
    func `cost status lines report missing data and errors per provider`() {
        let settings = MenuSettingsPanesFixture.settings(suite: "MenuSettingsPanesTests-cost-status")
        let store = MenuSettingsPanesFixture.store(settings: settings)
        defer { store.stopSharedSpendDashboardPublication() }
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let now = Date()
            #expect(CostSummarySettingsSection.statusLine(provider: .claude, store: store, now: now)
                == "Claude: no data yet")
            store._setTokenErrorForTesting("Scan timed out", provider: .codex)
            #expect(CostSummarySettingsSection.statusLine(provider: .codex, store: store, now: now)
                == "Codex: Scan timed out")
            for provider in CostSummarySettingsSection.costStatusProviders {
                let line = CostSummarySettingsSection.statusLine(provider: provider, store: store, now: now)
                #expect(line.hasPrefix(ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName))
                #expect(!line.contains("%@"))
            }
        }
    }

    @Test
    func `every menu bar search id has one entry on its pane`() {
        let entries = MenuBarSettingsPane.searchEntries
        let ids = entries.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(entries.allSatisfy { $0.pane == .menuBar })
        for id in MenuBarSettingsPane.SearchID.allCases {
            #expect(ids.contains(id.entryID), "\(id)")
        }
        #expect(ids.count == MenuBarSettingsPane.SearchID.allCases.count + 1)
        #expect(ids.contains("menuBar/overviewLayout"))
    }

    @Test
    func `every menu search id has one entry on its pane`() {
        let entries = MenuSettingsPane.searchEntries
        let ids = entries.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(entries.allSatisfy { $0.pane == .menu })
        for id in MenuSettingsPane.SearchID.allCases {
            #expect(ids.contains(id.entryID), "\(id)")
        }
        #expect(ids.count == MenuSettingsPane.SearchID.allCases.count + 1)
        // Quota warning markers moved to Alerts, and Overview layout to Menu Bar.
        #expect(!ids.contains("menu/quotaWarningMarkers"))
        #expect(!ids.contains("menu/overviewLayout"))
    }

    @Test
    func `search finds the overview layout under menu bar`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let found = SettingsSearchIndex.ranked(SettingsSearchIndex.allEntries, query: "overview layout")
            #expect(found.first?.id == "menuBar/overviewLayout")
            let hosts = SettingsSearchIndex.ranked(SettingsSearchIndex.allEntries, query: "ssh hosts")
            #expect(hosts.first?.id == "menu/agentSessionHosts")
        }
    }

    @Test(arguments: ["off", "switcher", "stacked"])
    func `combined icon rows and display options stay accessible`(mode: String) {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let merged = mode != "off"
            let presentation = MergedIconPresentation(
                mergeIcons: merged,
                iconStyle: .iconAndPercent,
                requestedStyle: mode == "stacked" ? .stacked : .switcher,
                eligibleProviders: [.codex, .claude],
                preferredTop: nil,
                preferredBottom: nil)
            let view = VStack(alignment: .leading, spacing: IUSpace.settingsSectionGap) {
                IUSettingsSection(L("section_combined_icon")) {
                    IUSettingsToggleRow(L("merge_icons_title"), isOn: .constant(merged))
                    IUSettingsRow(
                        L("merged_icon_style_title"),
                        disabledReason: MenuBarSettingsPane.mergedIconStyleDisabledReason(
                            mergeIcons: merged,
                            iconStyle: .iconAndPercent,
                            eligibleProviderCount: presentation.eligibleProviders.count))
                    {
                        IUPopUpButton(
                            MenuBarSettingsMenuOptions.mergedIconStyles.map { ($0, $0.label) },
                            selection: .constant(presentation.effectiveStyle))
                    }
                    .disabled(!presentation.canStack)
                    UnifiedIconSourcePicker(
                        selection: .constant(.frontmostApp),
                        disabledReason: MenuBarSettingsPane.iconSourceDisabledReason(
                            mergeIcons: merged,
                            effectiveStyle: presentation.effectiveStyle))
                        .disabled(!merged || presentation.effectiveStyle == .stacked)
                }
                IUSettingsSection(L("Display")) {
                    MenuBarLayoutDisplayOptions(
                        size: .constant(.small),
                        gap: .constant(.tight),
                        verticalAdjustment: .constant(0),
                        monospacedDigits: .constant(false),
                        showWindowLabels: .constant(true))
                }
            }
            .padding(IUSpace.settingsPagePadding)
            .frame(width: IUSize.settingsContentWidth)
            .environment(\.accessibilityEnabled, true)
            .background(IUColor.window)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            let text = MenuLayoutScreenshotRenderTests.accessibilityText(hosting)
            for key in [
                "merge_icons_title", "merged_icon_style_title", "merged_icon_source_title",
                "menu_bar_layout_size", "menu_bar_layout_gap", "menu_bar_layout_vertical_adjustment",
                "menu_bar_layout_monospaced_digits", "menu_bar_layout_show_window_labels",
            ] {
                #expect(text.contains(L(key)), "Missing accessible label: \(key) in \(mode)")
            }
            if !merged {
                #expect(text.contains("Turn on Merge icons first"))
            }
            if mode == "stacked" {
                #expect(text.contains(L("settings_reason_stacked_source", MergedIconDisplayStyle.stacked.label)))
            }
        }
    }
}

/// Settings and stores for the Menu Bar and Menu pane tests: dictionary-free isolated defaults, no Keychain,
/// manual refresh, and a chosen set of enabled providers.
@MainActor
enum MenuSettingsPanesFixture {
    static func settings(suite: String, enabled: [UsageProvider] = [.claude, .codex]) -> SettingsStore {
        let order = enabled + UsageProvider.allCases.filter { !enabled.contains($0) }
        let settings = testSettingsStore(
            suiteName: suite,
            config: CodexBarConfig(providers: order.map {
                ProviderConfig(id: $0.instanceID, enabled: enabled.contains($0))
            }),
            prepareDefaults: { defaults in
                defaults.set(AppGroupSupport.migrationVersion, forKey: AppGroupSupport.migrationVersionKey)
                defaults.set(true, forKey: "debugDisableKeychainAccess")
            })
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        return settings
    }

    static func store(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
    }
}
