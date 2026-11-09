import AppKit
import SwiftUI
import XCTest
@testable import CodexBar

@MainActor
final class AboutUpdatePreferenceStateTests: XCTestCase {
    /// The install switch reads Sparkle's saved choice (`SUAutomaticallyUpdate`), so opening About with checks off
    /// must leave that choice alone, and later changes from Settings or Sparkle's dialog must land in it. The switch
    /// is Internal UI's drawn `.iuSwitch`, not an `NSSwitch`, so its look is covered by `GeneralPanesSnapshotTests`.
    func test_installChoiceSurvivesOpeningAboutWhileChecksAreOffAndFollowsTheDialog() throws {
        let updater = try SparklePreferenceFixture(install: true, checks: false)
        defer { updater.cleanup() }
        let hosting = NSHostingView(rootView: AboutSettingsPage(updater: updater)
            .defaultAppStorage(updater.defaults).frame(width: 700, height: 680))
        hosting.frame = CGRect(x: 0, y: 0, width: 700, height: 680)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer {
            window.contentView = nil
            window.close()
        }
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertFalse(updater.automaticallyDownloadsUpdates)
        XCTAssertTrue(updater.defaults.bool(forKey: "SUAutomaticallyUpdate"))

        updater.defaults.set(true, forKey: "autoUpdateEnabled")
        self.drainUntil {
            hosting.layoutSubtreeIfNeeded()
            return updater.automaticallyDownloadsUpdates
        }
        XCTAssertTrue(updater.automaticallyDownloadsUpdates)
        XCTAssertTrue(updater.defaults.bool(forKey: "SUAutomaticallyUpdate"))

        updater.automaticallyDownloadsUpdates = false
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(updater.defaults.bool(forKey: "SUAutomaticallyUpdate"))
    }

    private func drainUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
}
