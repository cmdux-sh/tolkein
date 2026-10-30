import AppKit
import CodexBarCore
import SwiftUI

@MainActor
final class UsageBoardPanelController {
    let session: UsageBoardSession
    private var panel: UsageBoardPanel?
    private var monitors: [Any] = []
    private var isClosing = false
    private weak var anchor: NSStatusItem?

    init(session: UsageBoardSession) {
        self.session = session
    }

    var isVisible: Bool {
        self.panel?.isVisible == true
    }

    func anchoredStatusItem() -> NSStatusItem? {
        self.anchor
    }

    func present(anchoredTo item: NSStatusItem) {
        let panel = self.ensurePanel()
        self.anchor = item
        self.place(panel, anchoredTo: item)
        if !panel.isVisible {
            panel.alphaValue = 0
        }
        // Accessory menu-bar apps stay inactive until something asks. Activating lets the board
        // take key focus, and hidesOnDeactivate then dismisses it when another app is clicked.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        self.installMonitorsIfNeeded()
    }

    func dismiss() {
        guard !self.isClosing else { return }
        self.isClosing = true
        defer { self.isClosing = false }
        self.removeMonitors()
        self.panel?.orderOut(nil)
        self.anchor = nil
    }

    private func ensurePanel() -> NSPanel {
        if let panel = self.panel {
            return panel
        }
        let panel = UsageBoardPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: CGFloat(UsageBoardLayout.preferredWidth),
                height: CGFloat(UsageBoardLayout.preferredHeight)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isMovable = false
        panel.title = "CodexBar"
        panel.alphaValue = 0

        let hosting = NSHostingView(rootView: UsageBoardView(session: self.session))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: panel.contentView?.bounds ?? .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(
            srgbRed: 16 / 255,
            green: 18 / 255,
            blue: 24 / 255,
            alpha: 1).cgColor
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        container.addSubview(hosting)
        panel.contentView = container
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: content.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
        self.panel = panel
        return panel
    }

    private func place(_ panel: NSPanel, anchoredTo item: NSStatusItem) {
        guard let button = item.button, let window = button.window else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let width = CGFloat(UsageBoardLayout.fittedWidth(Double(visible.width)))
        let height = CGFloat(UsageBoardLayout.fittedHeight(Double(visible.height)))
        var originX = buttonFrame.maxX - width
        originX = min(max(visible.minX + 8, originX), visible.maxX - width - 8)
        var originY = buttonFrame.minY - height - 6
        if originY < visible.minY + 8 {
            originY = min(buttonFrame.maxY + 6, visible.maxY - height - 8)
        }
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
    }

    private func installMonitorsIfNeeded() {
        guard self.monitors.isEmpty else { return }
        let mouse = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // NSEvent is not Sendable. Copy the values the main actor needs, then hop.
            let windowID = event.window.map(ObjectIdentifier.init)
            let x = Double(event.locationInWindow.x)
            let y = Double(event.locationInWindow.y)
            let shouldClose = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                return self.shouldCloseBoard(windowID: windowID, x: x, y: y)
            }
            return shouldClose ? nil : event
        }
        let keys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let keyCode = event.keyCode
            let modifierBits = event.modifierFlags.rawValue
            let characters = event.charactersIgnoringModifiers
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                return self.handleKey(keyCode: keyCode, modifierBits: modifierBits, characters: characters)
            }
            return consumed ? nil : event
        }
        self.monitors = [mouse, keys].compactMap(\.self)
    }

    private func removeMonitors() {
        for monitor in self.monitors {
            NSEvent.removeMonitor(monitor)
        }
        self.monitors.removeAll()
    }

    private func shouldCloseBoard(windowID: ObjectIdentifier?, x: Double, y: Double) -> Bool {
        guard self.isVisible else { return false }
        if self.panel.map(ObjectIdentifier.init) == windowID { return false }
        if self.anchorContains(windowID: windowID, x: x, y: y) { return false }
        self.dismiss()
        return true
    }

    private func anchorContains(windowID: ObjectIdentifier?, x: Double, y: Double) -> Bool {
        guard let button = self.anchor?.button,
              let window = button.window,
              ObjectIdentifier(window) == windowID
        else { return false }
        let point = button.convert(NSPoint(x: x, y: y), from: nil)
        return button.bounds.contains(point)
    }

    private func handleKey(keyCode: UInt16, modifierBits: UInt, characters: String?) -> Bool {
        guard self.isVisible, self.panel?.isKeyWindow == true else { return false }
        if keyCode == 53 {
            self.session.onCommand(.close)
            return true
        }
        if keyCode == 125 {
            self.session.selectAdjacent(1)
            return true
        }
        if keyCode == 126 {
            self.session.selectAdjacent(-1)
            return true
        }
        let modifiers = NSEvent.ModifierFlags(rawValue: modifierBits)
            .intersection([.command, .option, .control, .shift])
        guard modifiers == .command else { return false }
        switch characters?.lowercased() {
        case "r":
            self.session.onCommand(.refresh)
            return true
        case ",":
            self.session.onCommand(.settings)
            return true
        case "q":
            self.session.onCommand(.quit)
            return true
        default:
            return false
        }
    }
}

private final class UsageBoardPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
