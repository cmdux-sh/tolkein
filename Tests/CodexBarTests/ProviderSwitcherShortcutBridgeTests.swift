import Carbon.HIToolbox
import CodexBarCore
import Foundation
import InternalUI
import Testing
@testable import CodexBar

@MainActor
struct ProviderSwitcherShortcutBridgeTests {
    private typealias Bridge = ProviderSwitcherShortcutBridge

    @Test func `every default shortcut shows in a recorder and stores back unchanged`() {
        for action in ProviderSwitcherShortcuts.actions {
            let stored = ProviderSwitcherShortcuts.defaults[action] ?? ""
            let shortcut = Bridge.shortcut(for: stored)
            #expect(shortcut != nil, "\(action)")
            #expect(Bridge.value(for: shortcut) == stored, "\(action)")
        }
        #expect(Bridge.shortcut(for: "left")?.displayString == "←")
        #expect(Bridge.shortcut(for: "cmd+1")?.displayString == "⌘1")
    }

    @Test func `recorded shortcuts store modifiers in the switcher order`() {
        let shortcut = IUShortcut("2", code: UInt16(kVK_ANSI_2), modifiers: [.command, .option])
        #expect(Bridge.value(for: shortcut) == "alt+cmd+2")

        let all = IUShortcut("K", code: UInt16(kVK_ANSI_K), modifiers: [.command, .shift, .option, .control])
        #expect(Bridge.value(for: all) == "ctrl+alt+shift+cmd+k")
        #expect(Bridge.shortcut(for: "ctrl+alt+shift+cmd+k") == all)
    }

    @Test func `keys are stored by the character they type`() {
        // A key recorded on another layout keeps its own code; the switcher matches by character.
        let azertyA = IUShortcut("A", code: UInt16(kVK_ANSI_Q), modifiers: [.control])
        #expect(Bridge.value(for: azertyA) == "ctrl+a")
        let comma = IUShortcut(",", code: UInt16(kVK_ANSI_Comma), modifiers: [.option])
        #expect(Bridge.value(for: comma) == "alt+,")
    }

    @Test func `clearing a shortcut turns its action off`() throws {
        #expect(Bridge.value(for: nil) == "none")
        #expect(Bridge.shortcut(for: "none") == nil)
        let result = try Bridge.assigning(nil, to: "next", in: ProviderSwitcherShortcuts.defaults).get()
        #expect(result["next"] == "none")
        #expect(result["previous"] == "left")
    }

    @Test func `keys the switcher can't read are turned down`() {
        let f5 = IUShortcut(IUShortcut.Key(code: UInt16(kVK_F5), name: "F5"), modifiers: [])
        let up = IUShortcut(IUShortcut.Key(code: UInt16(kVK_UpArrow), name: "↑"), modifiers: [.command])
        let cyrillic = IUShortcut("Й", code: UInt16(kVK_ANSI_Q), modifiers: [.command])
        for shortcut in [f5, up, cyrillic] {
            #expect(Bridge.value(for: shortcut) == nil)
            #expect(Bridge.assigning(shortcut, to: "next", in: ProviderSwitcherShortcuts.defaults)
                == .failure(.unsupportedKey))
        }
    }

    @Test func `reserved shortcuts are turned down`() {
        let reserved: [IUShortcut] = [
            IUShortcut("R", code: UInt16(kVK_ANSI_R), modifiers: .command),
            IUShortcut("Q", code: UInt16(kVK_ANSI_Q), modifiers: .command),
            IUShortcut(",", code: UInt16(kVK_ANSI_Comma), modifiers: .command),
            IUShortcut("H", code: UInt16(kVK_ANSI_H), modifiers: [.option, .command]),
            IUShortcut("W", code: UInt16(kVK_ANSI_W), modifiers: .command),
        ]
        for shortcut in reserved {
            #expect(
                Bridge.assigning(shortcut, to: "next", in: ProviderSwitcherShortcuts.defaults)
                    == .failure(.reserved(shortcut.displayString)),
                "\(shortcut.displayString)")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(Bridge.message(for: .reserved("⌘R")) == "⌘R is reserved for a menu or system command.")
        }
    }

    @Test func `a shortcut another action uses is turned down and names that action`() {
        let commandOne = IUShortcut("1", code: UInt16(kVK_ANSI_1), modifiers: .command)
        let result = Bridge.assigning(commandOne, to: "previous", in: ProviderSwitcherShortcuts.defaults)
        #expect(result == .failure(.duplicate(action: "select1")))
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(Bridge.message(for: .duplicate(action: "select1")) == "Already used by Select position 1.")
            #expect(Bridge.message(for: .unsupportedKey) == "Use a letter, a digit, ← or →.")
        }
    }

    @Test func `reassigning an action to its own shortcut is not a duplicate`() throws {
        let commandOne = IUShortcut("1", code: UInt16(kVK_ANSI_1), modifiers: .command)
        let result = try Bridge.assigning(commandOne, to: "select1", in: ProviderSwitcherShortcuts.defaults).get()
        #expect(result == ProviderSwitcherShortcuts.defaults)
    }

    @Test func `a valid shortcut is stored in the switcher format`() throws {
        let shiftRight = IUShortcut(IUShortcut.Key(code: UInt16(kVK_RightArrow), name: "→"), modifiers: .shift)
        let optionTwo = IUShortcut("2", code: UInt16(kVK_ANSI_2), modifiers: [.option, .command])
        var shortcuts = try Bridge.assigning(shiftRight, to: "next", in: ProviderSwitcherShortcuts.defaults).get()
        shortcuts = try Bridge.assigning(optionTwo, to: "select2", in: shortcuts).get()

        let settings = testSettingsStore(suiteName: "ProviderSwitcherShortcutBridgeTests")
        try settings.setProviderSwitcherShortcuts(shortcuts)

        #expect(settings.providerSwitcherShortcuts["next"] == "shift+right")
        #expect(settings.providerSwitcherShortcuts["select2"] == "alt+cmd+2")
        let stored = settings.userDefaults.dictionary(forKey: "switcherShortcuts") as? [String: String]
        #expect(stored == settings.providerSwitcherShortcuts)
        #expect(try ProviderSwitcherShortcuts.validated(stored ?? [:]) == stored)
    }

    @Test func `action labels match the old editor`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(Bridge.label(for: "previous") == "Previous provider")
            #expect(Bridge.label(for: "next") == "Next provider")
            #expect(Bridge.label(for: "select9") == "Select position 9")
        }
    }
}
