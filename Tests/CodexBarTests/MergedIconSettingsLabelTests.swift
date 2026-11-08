import AppKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct MergedIconSettingsLabelTests {
    @Test(arguments: [false, true])
    func `disabled row titles have lower contrast and remain readable`(dark: Bool) throws {
        let enabled = try Self.titleContrast(enabled: true, dark: dark)
        let disabled = try Self.titleContrast(enabled: false, dark: dark)
        #expect(disabled < enabled)
        #expect(disabled >= 3)
    }

    @Test(arguments: [false, true])
    func `disabled row titles and subtitles remain accessible`(enabled: Bool) {
        let hosting = NSHostingView(rootView: SettingsRowLabel("Synthetic title", subtitle: "Synthetic explanation")
            .disabled(!enabled)
            .environment(\.accessibilityEnabled, true))
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let text = MenuLayoutScreenshotRenderTests.accessibilityText(hosting)
        #expect(text.contains("Synthetic title"))
        #expect(text.contains("Synthetic explanation"))
    }

    private static func titleContrast(enabled: Bool, dark: Bool) throws -> Double {
        let renderer = ImageRenderer(content: SettingsRowLabel("Merged icon style")
            .disabled(!enabled)
            .padding(12)
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(dark ? Color.black : Color.white))
        renderer.scale = 2
        let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
        var contrast = 1.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let channels = [color.redComponent, color.greenComponent, color.blueComponent].map {
                    $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
                }
                let luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
                contrast = max(contrast, dark ? (luminance + 0.05) / 0.05 : 1.05 / (luminance + 0.05))
            }
        }
        return contrast
    }
}
