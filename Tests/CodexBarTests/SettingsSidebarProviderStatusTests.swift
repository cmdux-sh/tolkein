import CodexBarCore
import InternalUI
import Testing
@testable import CodexBar

struct SettingsSidebarProviderStatusTests {
    @Test
    func `Critical status describes provider service health`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.statusDescription(for: .critical)
                == "Provider service status: Critical issue")
        }
    }

    @Test
    func `Major status describes provider service health`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.statusDescription(for: .major)
                == "Provider service status: Major outage")
        }
    }

    @Test(arguments: [ProviderStatusIndicator.critical, .major, .minor, .maintenance, .unknown, .none])
    func `Provider row announces visible service status`(indicator: ProviderStatusIndicator) {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: true,
                indicator: indicator) == "Codex — Provider service status: \(indicator.label)")
        }
    }

    @Test
    func `Disabled provider keeps its existing accessibility label`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: false,
                statusChecksEnabled: true,
                indicator: .critical) == "Codex — Disabled")
        }
    }

    @Test
    func `Provider row omits service status when status checks are off`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: false,
                indicator: .major) == "Codex")
        }
    }

    @Test(arguments: [
        (ProviderStatusIndicator.none, MacStatusTone?.none),
        (.unknown, nil),
        (.minor, .warning),
        (.major, .error),
        (.critical, .error),
        (.maintenance, .neutral),
    ])
    func `service incidents show a tone and healthy or unknown status stays quiet`(
        indicator: ProviderStatusIndicator,
        tone: MacStatusTone?)
    {
        #expect(SettingsSidebarProviderStatus.tone(for: indicator) == tone)
    }

    @Test
    func `missing service status stays quiet like unknown`() {
        #expect(SettingsSidebarProviderStatus.tone(for: nil) == nil)
    }

    @Test
    func `refreshing shows a spinner before any other status`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let status = SettingsSidebarProviderStatus.resolve(
                isEnabled: true,
                isRefreshing: true,
                error: "Sign-in expired",
                statusChecksEnabled: true,
                indicator: .critical)
            #expect(status == SettingsSidebarProviderStatus(tone: .busy, text: "Refreshing"))
        }
    }

    @Test
    func `a failed refresh shows an error with its message`() {
        let status = SettingsSidebarProviderStatus.resolve(
            isEnabled: true,
            isRefreshing: false,
            error: "Sign-in expired",
            statusChecksEnabled: true,
            indicator: .minor)
        #expect(status == SettingsSidebarProviderStatus(tone: .error, text: "Sign-in expired"))
    }

    @Test
    func `service incidents carry their status text for the tooltip`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let status = SettingsSidebarProviderStatus.resolve(
                isEnabled: true,
                isRefreshing: false,
                error: nil,
                statusChecksEnabled: true,
                indicator: .major)
            #expect(status == SettingsSidebarProviderStatus(
                tone: .error,
                text: "Provider service status: Major outage"))
        }
    }

    @Test
    func `disabled providers and status checks that are off show no status`() {
        #expect(SettingsSidebarProviderStatus.resolve(
            isEnabled: false,
            isRefreshing: false,
            error: "Sign-in expired",
            statusChecksEnabled: true,
            indicator: .critical) == nil)
        #expect(SettingsSidebarProviderStatus.resolve(
            isEnabled: true,
            isRefreshing: false,
            error: nil,
            statusChecksEnabled: false,
            indicator: .critical) == nil)
        #expect(SettingsSidebarProviderStatus.resolve(
            isEnabled: true,
            isRefreshing: false,
            error: nil,
            statusChecksEnabled: true,
            indicator: ProviderStatusIndicator.none) == nil)
    }

    @Test
    func `Missing status is unknown rather than operational`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.statusDescription(for: nil)
                == "Provider service status: Status unknown")
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: true,
                indicator: nil) == "Codex — Provider service status: Status unknown")
        }
    }

    @Test
    func `Fetched healthy status remains operational`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.statusDescription(for: ProviderStatusIndicator.none)
                == "Provider service status: Operational")
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: true,
                indicator: ProviderStatusIndicator.none) == "Codex — Provider service status: Operational")
        }
    }
}
