import AppKit
import Carbon.HIToolbox
import Foundation
import InternalUI
import KeyboardShortcuts
import Testing
@testable import CodexBar

@MainActor
struct KeyboardShortcutsBundleTests {
    @Test func `recorder initializes without crashing`() {
        _ = KeyboardShortcuts.RecorderCocoa(for: .init("test.keyboardshortcuts.bundle"))
    }

    @Test func `open menu shortcut round trips between the recorder and KeyboardShortcuts`() {
        let recorded = MacShortcut("K", code: UInt16(kVK_ANSI_K), modifiers: [.option, .command])
        let stored = OpenMenuShortcutBridge.keyboardShortcut(recorded)

        #expect(stored.carbonKeyCode == kVK_ANSI_K)
        #expect(stored.modifiers == [.option, .command])
        #expect(OpenMenuShortcutBridge.macShortcut(stored, character: { _ in "k" }) == recorded)
    }

    @Test func `every modifier crosses the bridge`() {
        let all: MacShortcut.Modifiers = [.control, .option, .shift, .command]
        let stored = OpenMenuShortcutBridge.keyboardShortcut(
            MacShortcut("J", code: UInt16(kVK_ANSI_J), modifiers: all))

        #expect(stored.modifiers == [.control, .option, .shift, .command])
        #expect(OpenMenuShortcutBridge.macShortcut(stored, character: { _ in "j" }).modifiers == all)
    }

    @Test func `special keys are named by their code, not the layout`() {
        let f5 = OpenMenuShortcutBridge.macShortcut(
            KeyboardShortcuts.Shortcut(.f5, modifiers: [.command]),
            character: { _ in nil })
        #expect(f5.key == MacShortcut.Key(code: UInt16(kVK_F5), name: "F5"))

        let left = OpenMenuShortcutBridge.macShortcut(
            KeyboardShortcuts.Shortcut(.leftArrow, modifiers: [.control]),
            character: { _ in "x" })
        #expect(left.key.name == "←")
        #expect(left.displayString == "⌃←")
    }

    @Test func `a key the layout can't name keeps a visible name`() {
        let shortcut = OpenMenuShortcutBridge.macShortcut(
            KeyboardShortcuts.Shortcut(.help, modifiers: [.command]),
            character: { _ in nil })
        #expect(!shortcut.key.name.isEmpty)
        #expect(shortcut.key.code == UInt16(kVK_Help))
    }

    @Test func `the bridge keeps KeyboardShortcuts storage`() {
        let name = KeyboardShortcuts.Name("test.keyboardshortcuts.bridge")
        defer { KeyboardShortcuts.reset(name) }
        let stored = OpenMenuShortcutBridge.keyboardShortcut(
            MacShortcut("M", code: UInt16(kVK_ANSI_M), modifiers: [.control, .option]))

        KeyboardShortcuts.setShortcut(stored, for: name)

        #expect(KeyboardShortcuts.getShortcut(for: name) == stored)
        #expect(UserDefaults.standard.object(forKey: "KeyboardShortcuts_test.keyboardshortcuts.bridge") != nil)
    }

    @Test func `open menu verdict keeps the KeyboardShortcuts recorder rules`() {
        let candidate = KeyboardShortcuts.Shortcut(.k, modifiers: [.option, .command])
        let other = KeyboardShortcuts.Shortcut(.j, modifiers: [.option, .command])
        func verdict(
            current: KeyboardShortcuts.Shortcut?,
            menuItem: String? = nil,
            disallowed: Bool = false,
            system: Bool = false) -> OpenMenuShortcutBridge.Verdict
        {
            OpenMenuShortcutBridge.verdict(
                for: candidate,
                current: current,
                conflictingMenuItem: menuItem,
                isDisallowed: disallowed,
                isTakenBySystem: system)
        }

        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(verdict(current: other) == .accept)
            #expect(verdict(current: other, menuItem: "Settings…", system: true)
                == .reject("Already used by the “Settings…” menu item."))
            // Re-recording the current shortcut skips the menu check, as KeyboardShortcuts does.
            #expect(verdict(current: candidate, menuItem: "Settings…") == .accept)
            #expect(verdict(current: nil, disallowed: true, system: true)
                == .reject("Combine Option with Command or Control."))
            #expect(verdict(current: nil, system: true) == .confirmSystemConflict)
        }
    }

    @Test func `menu conflicts are found in submenus and through uppercase key equivalents`() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let redo = NSMenuItem(title: "Redo", action: nil, keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = .command
        submenu.addItem(redo)
        edit.submenu = submenu
        menu.addItem(edit)

        let comma = KeyboardShortcuts.Shortcut(.comma, modifiers: [.command])
        let shiftZ = KeyboardShortcuts.Shortcut(.z, modifiers: [.shift, .command])
        let optionComma = KeyboardShortcuts.Shortcut(.comma, modifiers: [.option, .command])

        #expect(OpenMenuShortcutBridge.menuItem(matching: comma, in: menu)?.title == "Settings…")
        #expect(OpenMenuShortcutBridge.menuItem(matching: shiftZ, in: menu)?.title == "Redo")
        #expect(OpenMenuShortcutBridge.menuItem(matching: optionComma, in: menu) == nil)
    }

    @Test func `option only hotkeys are disallowed only for sandboxed macOS 15_0 and 15_1`() {
        let optionOnly = KeyboardShortcuts.Shortcut(.k, modifiers: [.option, .shift])
        let withCommand = KeyboardShortcuts.Shortcut(.k, modifiers: [.option, .command])
        let early = OperatingSystemVersion(majorVersion: 15, minorVersion: 1, patchVersion: 0)
        let later = OperatingSystemVersion(majorVersion: 15, minorVersion: 2, patchVersion: 0)

        #expect(OpenMenuShortcutBridge.isDisallowed(optionOnly, version: early, sandboxed: true))
        #expect(!OpenMenuShortcutBridge.isDisallowed(withCommand, version: early, sandboxed: true))
        #expect(!OpenMenuShortcutBridge.isDisallowed(optionOnly, version: later, sandboxed: true))
        #expect(!OpenMenuShortcutBridge.isDisallowed(optionOnly, version: early, sandboxed: false))
    }
}
