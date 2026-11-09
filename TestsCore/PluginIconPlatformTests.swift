import CodexBarCore
import Testing

struct PluginIconPlatformTests {
    @Test
    func `SVG icons are validated only on macOS`() {
        let icon = #"<svg viewBox="0 0 24 24"><path d="M0 0h24v24H0z"/></svg>"#
        #expect(ProviderPluginIconSVG.isValid(icon))
    }
}
