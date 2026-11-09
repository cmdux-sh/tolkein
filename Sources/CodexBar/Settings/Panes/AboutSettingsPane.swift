import AppKit
import InternalUI
import SwiftUI

/// About: the app, its updates, its links and the credit to CodexBar. Acknowledgements open in a sheet.
@MainActor
struct AboutSettingsPane: View {
    let context: SettingsPaneContext

    var body: some View {
        AboutSettingsPage(updater: self.context.updater)
    }
}

extension AboutSettingsPane {
    static var searchEntries: [SettingsSearchEntry] {
        let pane = SettingsPane.about
        let updates = L("section_updates")
        let links = L("section_links")
        return [
            .paneTitle(pane),
            pane.searchEntry("automaticChecks", L("check_updates_auto"), keywords: updates),
            pane.searchEntry("automaticInstall", L("install_updates_auto"), keywords: updates),
            pane.searchEntry("updateChannel", L("update_channel"), keywords: updates),
            pane.searchEntry("checkForUpdates", L("check_for_updates"), keywords: updates, L("update_check_title")),
            pane.searchEntry("github", L("link_github"), keywords: links),
            pane.searchEntry("acknowledgements", L("link_acknowledgements"), keywords: links),
        ]
    }

    /// The product name About shows. The bundle, targets and CLI keep their CodexBar names for now.
    static let appName = "Tolkein"
    /// About's only external link; the app icon opens it too.
    static let projectHomeURL = "https://github.com/cmdux-sh/tolkein"
    /// The project Tolkein is based on, linked from the MIT credit line.
    static let originalProjectURL = "https://github.com/steipete/CodexBar"

    /// "Based on CodexBar by Peter Steinberger (MIT License)", linked to the original project.
    static func creditText() -> AttributedString {
        var credit = AttributedString(L("about_based_on_codexbar"))
        credit.link = URL(string: Self.originalProjectURL)
        return credit
    }
}

/// Where About used to navigate inside the pane. Acknowledgements now open as a sheet, so About no longer sets it;
/// `PreferencesSelection` still carries the route for its history.
enum AboutRoute: Hashable {
    case acknowledgements
}

@MainActor
struct AboutSettingsPage: View {
    /// The app icon's side in the hero.
    private static let iconSide = IUSize.gaugeRegular

    let updater: UpdaterProviding
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled: Bool = true
    @AppStorage(UpdateChannel.userDefaultsKey)
    private var updateChannelRaw: String = UpdateChannel.defaultChannel.rawValue
    @AppStorage("SUAutomaticallyUpdate") private var automaticInstallEnabled = true
    @State private var didLoadUpdaterState = false
    @State private var showsAcknowledgements = false

    var body: some View {
        IUSettingsPage(L("tab_about")) {
            self.hero
            self.updatesSection
            IUSettingsSection(L("section_links")) {
                IUSettingsLinkRow(L("link_github"), systemImage: "chevron.left.slash.chevron.right") {
                    self.openProjectHome()
                }
                .settingsAnchor("about/github")
                IUSettingsLinkRow(L("link_acknowledgements"), systemImage: "heart.text.square") {
                    self.showsAcknowledgements = true
                }
                .settingsAnchor("about/acknowledgements")
            }
            Text(AboutSettingsPane.creditText() + AttributedString("\n" + L("copyright")))
                .font(IUTextRole.caption.font)
                .foregroundStyle(IUColor.muted)
                .tint(IUColor.accent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            guard !self.didLoadUpdaterState else { return }
            // Align Sparkle's check flag with the persisted preference on first load.
            UpdaterPreferenceSync.applyAutomaticChecks(self.autoUpdateEnabled, to: self.updater)
            self.didLoadUpdaterState = true
        }
        .onChange(of: self.autoUpdateEnabled) { _, newValue in
            UpdaterPreferenceSync.applyAutomaticChecks(newValue, to: self.updater)
        }
        .sheet(isPresented: self.$showsAcknowledgements) {
            AcknowledgementsSheet(acknowledgements: Acknowledgement.load())
        }
    }

    private var hero: some View {
        VStack(spacing: IUSpace.unit * 2) {
            if let image = NSApplication.shared.applicationIconImage {
                Button(action: self.openProjectHome) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: Self.iconSide, height: Self.iconSide)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(L("link_github"))
                .accessibilityLabel(L("link_github"))
            }
            VStack(spacing: IUSpace.unit) {
                Text(verbatim: AboutSettingsPane.appName)
                    .font(IUTextRole.display.font)
                    .foregroundStyle(IUColor.primary)
                IUText(String(format: L("version_format"), AppVersion.displayString), muted: true)
                    .monospacedDigit()
                    .textSelection(.enabled)
                if let buildTimestamp = Self.buildTimestamp {
                    IUText(String(format: L("built_format"), buildTimestamp), role: .caption, muted: true)
                }
                IUText(L("about_tagline"), role: .caption, muted: true)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IUSpace.unit * 2)
        .accessibilityElement(children: .contain)
    }

    private var updatesSection: some View {
        IUSettingsSection(L("section_updates")) {
            if self.offersUpdates {
                IUSettingsToggleRow(L("check_updates_auto"), isOn: self.$autoUpdateEnabled)
                    .settingsAnchor("about/automaticChecks")
            }
            if self.updater.isAvailable {
                // Sparkle only: Homebrew installs are upgraded through `brew`, never silently.
                IUSettingsToggleRow(
                    L("install_updates_auto"),
                    subtitle: L("install_updates_auto_subtitle"),
                    disabledReason: L("install_updates_needs_checks"),
                    isOn: Binding(
                        get: { self.automaticInstallEnabled },
                        set: { self.updater.automaticallyDownloadsUpdates = $0 }))
                    // Installs need a background check to find the update, so the choice is moot while checks are off.
                        .disabled(!self.autoUpdateEnabled)
                        .settingsAnchor("about/automaticInstall")
                IUSettingsRow(L("update_channel"), subtitle: self.updateChannel.description) {
                    IUPopUpButton(
                        UpdateChannel.allCases.map { ($0, $0.displayName) },
                        selection: self.updateChannelBinding)
                }
                .settingsAnchor("about/updateChannel")
            }
            if self.offersUpdates {
                IUSettingsRow(L("update_check_title"), disabledReason: L("update_check_busy")) {
                    Button(L("check_for_updates")) { self.updater.checkForUpdates(nil) }
                        .buttonStyle(.iu())
                }
                .disabled(self.isHomebrewBusy)
                .settingsAnchor("about/checkForUpdates")
            }
            if let homebrewUpdater = self.homebrewUpdater {
                AboutHomebrewUpdateStatusView(updater: homebrewUpdater)
            } else if !self.updater.isAvailable {
                AboutUpdatesUnavailableView(reason: self.updater.unavailableReason ?? L("updates_unavailable"))
                    .buttonStyle(.iuIcon)
            }
        }
    }

    private var homebrewUpdater: HomebrewUpdaterController? {
        self.updater as? HomebrewUpdaterController
    }

    /// Sparkle, or Homebrew's own checks: either way the app can look for a new version.
    private var offersUpdates: Bool {
        self.updater.isAvailable || self.homebrewUpdater != nil
    }

    private var isHomebrewBusy: Bool {
        self.homebrewUpdater?.phase == .checking || self.homebrewUpdater?.phase == .installing
    }

    private var updateChannel: UpdateChannel {
        UpdateChannel(rawValue: self.updateChannelRaw) ?? .stable
    }

    private var updateChannelBinding: Binding<UpdateChannel> {
        Binding(
            get: { self.updateChannel },
            set: { newValue in
                self.updateChannelRaw = newValue.rawValue
                self.updater.checkForUpdates(nil)
            })
    }

    private static var buildTimestamp: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CodexBuildTimestamp") as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: raw) else { return raw }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }

    private func openProjectHome() {
        guard let url = URL(string: AboutSettingsPane.projectHomeURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
