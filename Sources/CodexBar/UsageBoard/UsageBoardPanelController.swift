import AppKit
import CodexBarCore
import SwiftUI

@MainActor
final class UsageBoardPanelController {
    private let session: UsageBoardSession
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
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return event }
                if self.eventIsInsidePanel(event) || self.eventIsInsideAnchor(event) {
                    return event
                }
                self.dismiss()
                return nil
            }
        }
        let keys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.isVisible, self.panel?.isKeyWindow == true else { return event }
                return self.handleKey(event)
            }
        }
        self.monitors = [mouse, keys].compactMap(\.self)
    }

    private func removeMonitors() {
        for monitor in self.monitors {
            NSEvent.removeMonitor(monitor)
        }
        self.monitors.removeAll()
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 {
            self.session.onCommand(.close)
            return nil
        }
        if event.keyCode == 125 {
            self.session.selectAdjacent(1)
            return nil
        }
        if event.keyCode == 126 {
            self.session.selectAdjacent(-1)
            return nil
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers == .command else { return event }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "r":
            self.session.onCommand(.refresh)
            return nil
        case ",":
            self.session.onCommand(.settings)
            return nil
        case "q":
            self.session.onCommand(.quit)
            return nil
        default:
            return event
        }
    }

    private func eventIsInsidePanel(_ event: NSEvent) -> Bool {
        event.window === self.panel
    }

    private func eventIsInsideAnchor(_ event: NSEvent) -> Bool {
        guard let button = self.anchor?.button, let window = button.window, event.window === window else {
            return false
        }
        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
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
