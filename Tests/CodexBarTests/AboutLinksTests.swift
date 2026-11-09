import AppKit
import InternalUI
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct AboutLinksTests {
    @Test
    func `about names Tolkein and links to its repository`() {
        #expect(AboutSettingsPane.appName == "Tolkein")
        #expect(AboutSettingsPane.projectHomeURL == "https://github.com/cmdux-sh/tolkein")
    }

    @Test
    func `the CodexBar credit links to the original project`() throws {
        #expect(AboutSettingsPane.originalProjectURL == "https://github.com/steipete/CodexBar")
        let credit = CodexBarLocalizationOverride.$appLanguage.withValue("en") { AboutSettingsPane.creditText() }
        #expect(String(credit.characters) == "Based on CodexBar by Peter Steinberger (MIT License)")
        let expected = try #require(URL(string: "https://github.com/steipete/CodexBar"))
        #expect(credit.runs.compactMap(\.link) == [expected])
    }

    @Test
    func `about and acknowledgements keep the CodexBar credit`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(L("about_based_on_codexbar") == "Based on CodexBar by Peter Steinberger (MIT License)")
            #expect(L("acknowledgements_footer") == "Tolkein is built with these open-source projects.")
            #expect(L("copyright").contains("Peter Steinberger"))
        }
    }

    @Test
    func `about update status names Tolkein`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(L("Tolkein is up to date") == "Tolkein is up to date")
            #expect(String(format: L("Tolkein %@ is available"), "1.2.3") == "Tolkein 1.2.3 is available")
            #expect(L("About Tolkein") == "About Tolkein")
            #expect(L("quit_app") == "Quit Tolkein")
        }
    }

    @Test
    func `about links render without opening a browser`() throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_ABOUT_WEBSITE_PROOF_DIR"] else { return }
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let url = AboutSettingsPane.projectHomeURL
            let png = try #require(MacSnapshot.png(
                VStack(alignment: .leading, spacing: MacSpace.settingsSectionGap) {
                    MacSettingsSection(L("section_links")) {
                        MacSettingsLinkRow(L("link_github"), systemImage: "chevron.left.slash.chevron.right") {}
                    }
                    Text(verbatim: "Configured destination (proof annotation)").font(MacTextRole.caption.font)
                    Text(url).font(MacTextRole.body.font).monospaced()
                }
                .padding(MacSpace.settingsPagePadding),
                appearance: .light,
                width: 530))
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try png.write(to: output.appendingPathComponent("about.png"))
        }
    }
}
