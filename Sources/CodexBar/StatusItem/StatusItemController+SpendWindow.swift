import AppKit

extension StatusItemController {
    /// Opens the Spend window, which replaced Settings → Usage & Spend. Closes any open menu first, as Settings does.
    func openSpendWindow(_ destination: SpendWindowDestination) {
        _ = self.closeOpenMenusFromShortcutIfNeeded()
        if let spendWindowOpenHandler {
            spendWindowOpenHandler(destination)
            return
        }
        SpendWindowController.opener(settings: self.settings, store: self.store)(destination)
    }

    /// The Overview spend card's menu action (click, Return or VoiceOver press).
    @objc func showSpendWindow(_: NSMenuItem?) {
        self.openSpendWindow(.dashboard)
    }
}
