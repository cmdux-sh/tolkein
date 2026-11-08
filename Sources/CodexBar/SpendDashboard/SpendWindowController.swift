import AppKit
import SwiftUI

/// What the Spend window shows when it opens.
enum SpendWindowDestination {
    /// The dashboard (time range, currency sections, heatmap).
    case dashboard
    /// The session browser for one account's cost history, opened from the menu's cost history.
    case sessions(SessionUsageBrowserContext, sessionID: String?)

    /// The session request this destination puts on `SessionUsageNavigation`; nil shows the dashboard.
    var sessionRequest: SessionUsageNavigation.Request? {
        switch self {
        case .dashboard: nil
        case let .sessions(context, sessionID): .init(context: context, sessionID: sessionID)
        }
    }
}

/// Opens the Spend window. Settings and the menu call one of these instead of building the window, so tests can
/// record the destination without presenting anything.
typealias SpendWindowOpening = @MainActor (SpendWindowDestination) -> Void

enum SpendWindowIdentity {
    static let identifier = "com.cmdux.tolkein.spend"
    static let frameAutosaveName = "Tolkein.SpendWindow"
    static let defaultSize = NSSize(width: 980, height: 820)
    static let minimumSize = NSSize(width: 640, height: 480)
}

/// Owns the one Spend window. Opening it again brings the same window forward; closing it keeps the frame
/// (autosaved under `SpendWindowIdentity.frameAutosaveName`) and releases the SwiftUI content, so the dashboard's
/// background catch-up returns to its normal pace.
@MainActor
final class SpendWindowController: NSWindowController, NSWindowDelegate {
    enum Outcome: Equatable {
        case created
        case reused
    }

    typealias WindowFactory = @MainActor () -> NSWindow
    typealias WindowAction = @MainActor (NSWindow) -> Void

    /// The app's Spend window. Built on first use from the app's settings and store.
    private static var sharedController: SpendWindowController?

    private let navigation: SessionUsageNavigation
    private let makeWindow: WindowFactory
    private let presentWindow: WindowAction
    private var frameWhenClosed: NSRect?

    init(
        navigation: SessionUsageNavigation = .shared,
        makeWindow: @escaping WindowFactory,
        presentWindow: @escaping WindowAction = SpendWindowController.presentLive)
    {
        self.navigation = navigation
        self.makeWindow = makeWindow
        self.presentWindow = presentWindow
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The live opener for Settings and the menu: the shared window, built from `settings` and `store` the first time.
    static func opener(settings: SettingsStore, store: UsageStore) -> SpendWindowOpening {
        { destination in
            self.shared(settings: settings, store: store).open(destination)
        }
    }

    static func shared(settings: SettingsStore, store: UsageStore) -> SpendWindowController {
        if let sharedController { return sharedController }
        let controller = SpendWindowController {
            self.makeLiveWindow(settings: settings, store: store)
        }
        self.sharedController = controller
        return controller
    }

    @discardableResult
    func open(_ destination: SpendWindowDestination) -> Outcome {
        self.navigation.request = destination.sessionRequest
        let outcome: Outcome
        let window: NSWindow
        if self.isWindowLoaded, let existingWindow = self.window {
            window = existingWindow
            outcome = .reused
        } else {
            window = self.makeWindow()
            window.identifier = NSUserInterfaceItemIdentifier(SpendWindowIdentity.identifier)
            window.isReleasedWhenClosed = false
            window.delegate = self
            if let frameWhenClosed {
                window.setFrame(frameWhenClosed, display: false)
            }
            self.window = window
            outcome = .created
        }
        self.presentWindow(window)
        return outcome
    }

    func windowWillClose(_ notification: Notification) {
        guard self.isWindowLoaded,
              let window = notification.object as? NSWindow,
              window === self.window
        else { return }
        let frame = window.frame
        self.frameWhenClosed = frame
        // Detaching SwiftUI ends the view's visible lifetime (catch-up returns to automatic) and can resize the
        // window, so restore the frame the autosave should keep.
        window.contentViewController = nil
        window.contentView = NSView()
        window.setFrame(frame, display: false)
        self.window = nil
    }

    // MARK: - Live window

    private static func makeLiveWindow(settings: SettingsStore, store: UsageStore) -> NSWindow {
        let rootView = SpendWindowView(settings: settings, store: store).codexBarLocalized()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SpendWindowIdentity.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.contentViewController = NSHostingController(rootView: rootView)
        window.title = L("Spend")
        window.minSize = SpendWindowIdentity.minimumSize
        if !window.setFrameUsingName(SpendWindowIdentity.frameAutosaveName) {
            window.setContentSize(SpendWindowIdentity.defaultSize)
            window.center()
        }
        window.setFrameAutosaveName(SpendWindowIdentity.frameAutosaveName)
        return window
    }

    /// Shows the Dock icon while the window is up (as Settings does), then brings the window forward on the
    /// current Space.
    static func presentLive(_ window: NSWindow) {
        let attempt = DockIconController.shared.promote(presentationTimeout: .seconds(2))
        SettingsWindowStageBehavior.present(window)
        NSApp.activate(ignoringOtherApps: true)
        DockIconController.shared.finishPresentationAttempt(attempt)
    }
}
