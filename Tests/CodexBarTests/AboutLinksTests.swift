import AppKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct AboutLinksTests {
    @Test
    func `about names Tolkein and links to its repository`() {
        #expect(AboutPane.appName == "Tolkein")
        #expect(AboutPane.projectHomeURL == "https://github.com/cmdux-sh/tolkein")
    }

    @Test
    func `about lists only the GitHub link and acknowledgements`() throws {
        let source = try Self.aboutSource()
        let rows = source.components(separatedBy: "AboutLinkRow(").dropFirst()
        #expect(rows.count == 1)
        #expect(source.contains("title: L(\"link_github\")"))
        #expect(source.contains("url: Self.projectHomeURL"))
        #expect(source.contains("self.selection.showAcknowledgements()"))
        for retired in ["link_website", "link_twitter", "link_email", "mailto:", "twitter.com", "codexbar.app"] {
            #expect(!source.contains(retired), "\(retired)")
        }
        #expect(!source.contains("steipete/CodexBar"))
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
            let url = AboutPane.projectHomeURL
            let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 16) {
                AboutLinkRow(icon: "chevron.left.slash.chevron.right", title: L("link_github"), url: url)
                Divider()
                Text(verbatim: "Configured destination (proof annotation)").font(.caption)
                Text(url).font(.system(.body, design: .monospaced))
            }
            .padding(24)
            .frame(width: 530)
            .environment(\.colorScheme, .light)
            .background(Color.white))
            renderer.scale = 2
            let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try png.write(to: output.appendingPathComponent("about.png"))
        }
    }

    private static func aboutSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Sources/CodexBar/Settings/PreferencesAboutPane.swift"),
            encoding: .utf8)
    }
}
