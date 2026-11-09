import AppKit
import Carbon.HIToolbox
import CodexBarCore
import InternalUI
import KeyboardShortcuts

// MARK: - Open menu (global hotkey)

/// Bridges Internal UI's `MacShortcut`, which `MacShortcutRecorder` edits, to KeyboardShortcuts' `Shortcut`, which
/// stores and registers the global Open menu hotkey. The recorder only edits; KeyboardShortcuts keeps the stored value
/// (`KeyboardShortcuts_openMenu`) and the hotkey registration, so the hotkey behaves as before.
///
/// KeyboardShortcuts' own recorder also checked each new shortcut against the app's main menu, the macOS 15.0–15.1
/// sandbox restriction and the system-wide shortcuts. `verdict(for:current:conflictingMenuItem:isDisallowed:
/// isTakenBySystem:)` keeps those rules in the same order; `MacShortcutRecorder` already turns down a key without ⌘,
/// ⌥ or ⌃ (function keys exempt), as that recorder did.
@MainActor
enum OpenMenuShortcutBridge {
    /// What to do with a newly recorded shortcut.
    enum Verdict: Equatable {
        case accept
        /// The shortcut can't be used; the message says why.
        case reject(String)
        /// macOS already uses the shortcut system-wide. It is saved only if the person confirms.
        case confirmSystemConflict
    }

    /// The shortcut as the recorder shows it. `character` names a plain key on the current keyboard layout; special
    /// keys (arrows, Return, function keys) are named by their code.
    static func macShortcut(
        _ shortcut: KeyboardShortcuts.Shortcut,
        character: (KeyboardShortcuts.Shortcut) -> String? = { $0.nsMenuItemKeyEquivalent }) -> MacShortcut
    {
        let code = UInt16(clamping: shortcut.carbonKeyCode)
        let key = MacShortcut.Key(code: code, character: character(shortcut))
            ?? MacShortcut.Key(code: code, name: self.fallbackName(shortcut))
        return MacShortcut(key, modifiers: MacShortcut.Modifiers(shortcut.modifiers))
    }

    /// The shortcut as KeyboardShortcuts stores it: the same key code and modifiers.
    static func keyboardShortcut(_ shortcut: MacShortcut) -> KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(
            KeyboardShortcuts.Key(rawValue: Int(shortcut.key.code)),
            modifiers: self.modifierFlags(shortcut.modifiers))
    }

    static func modifierFlags(_ modifiers: MacShortcut.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
    }

    /// KeyboardShortcuts' recorder rules, in its order: a main-menu item using the shortcut blocks it (re-recording the
    /// current shortcut skips this check), then the sandboxed macOS 15.0–15.1 Option restriction, then a system-wide
    /// shortcut asks for confirmation.
    static func verdict(
        for candidate: KeyboardShortcuts.Shortcut,
        current: KeyboardShortcuts.Shortcut?,
        conflictingMenuItem: String?,
        isDisallowed: Bool,
        isTakenBySystem: Bool) -> Verdict
    {
        if candidate != current, let conflictingMenuItem {
            return .reject(L("open_menu_shortcut_menu_conflict", conflictingMenuItem))
        }
        if isDisallowed {
            return .reject(L("open_menu_shortcut_disallowed"))
        }
        return isTakenBySystem ? .confirmSystemConflict : .accept
    }

    /// The verdict for a shortcut recorded in the running app, checked against `NSApp.mainMenu` and the enabled
    /// system shortcuts.
    static func liveVerdict(for candidate: KeyboardShortcuts.Shortcut) -> Verdict {
        let current = KeyboardShortcuts.getShortcut(for: .openMenu)
        let menuItem = NSApp.mainMenu.flatMap { self.menuItem(matching: candidate, in: $0) }
        return self.verdict(
            for: candidate,
            current: current,
            conflictingMenuItem: menuItem?.title,
            isDisallowed: self.isDisallowed(candidate),
            isTakenBySystem: candidate.isTakenBySystem)
    }

    /// The first menu item, searching submenus, whose key equivalent is the shortcut. An uppercase key equivalent
    /// counts as Shift, as AppKit treats it.
    static func menuItem(matching shortcut: KeyboardShortcuts.Shortcut, in menu: NSMenu) -> NSMenuItem? {
        let keyEquivalent = shortcut.nsMenuItemKeyEquivalent
        for item in menu.items {
            var itemKey = item.keyEquivalent
            var itemModifiers = item.keyEquivalentModifierMask
            if shortcut.modifiers.contains(.shift), itemKey.lowercased() != itemKey {
                itemKey = itemKey.lowercased()
                itemModifiers.insert(.shift)
            }
            if keyEquivalent == itemKey, shortcut.modifiers == itemModifiers {
                return item
            }
            if let submenu = item.submenu, let match = self.menuItem(matching: shortcut, in: submenu) {
                return match
            }
        }
        return nil
    }

    /// Sandboxed apps on macOS 15.0 and 15.1 can't register a hotkey whose only modifiers are Option and Shift.
    static func isDisallowed(
        _ shortcut: KeyboardShortcuts.Shortcut,
        version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        sandboxed: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil) -> Bool
    {
        guard version.majorVersion == 15, version.minorVersion <= 1, sandboxed,
              shortcut.modifiers.contains(.option)
        else { return false }
        return shortcut.modifiers.isDisjoint(with: [.command, .control, .function, .capsLock])
    }

    /// The key's name from KeyboardShortcuts' description ("⌥⌘K" without "⌥⌘"), for keys the layout can't name.
    private static func fallbackName(_ shortcut: KeyboardShortcuts.Shortcut) -> String {
        let description = shortcut.description
        let prefix = shortcut.modifiers.ks_symbolicRepresentation
        let name = description.hasPrefix(prefix) ? String(description.dropFirst(prefix.count)) : description
        return name.isEmpty ? "?" : name
    }
}

// MARK: - Provider switcher (menu-local)

/// Bridges `MacShortcut` to the stored provider-switcher format (`"alt+cmd+2"`, `"left"`, `"none"`), and checks a
/// newly recorded shortcut with `ProviderSwitcherShortcuts`' rules before it is stored.
enum ProviderSwitcherShortcutBridge {
    /// Why a recorded shortcut can't be assigned to an action.
    enum Issue: Error, Equatable {
        /// The switcher only understands letters, digits, a comma, ← and →.
        case unsupportedKey
        /// Refresh, Settings, Quit and a few system shortcuts are reserved.
        case reserved(String)
        /// Another action already uses the shortcut.
        case duplicate(action: String)
    }

    private static let modifierNames: [(MacShortcut.Modifiers, String)] = [
        (.control, "ctrl"), (.option, "alt"), (.shift, "shift"), (.command, "cmd"),
    ]

    private static let leftArrow = MacShortcut.Key(code: UInt16(kVK_LeftArrow), name: "←")
    private static let rightArrow = MacShortcut.Key(code: UInt16(kVK_RightArrow), name: "→")

    /// US-layout key codes for the keys the switcher accepts, so a stored shortcut can be shown as key caps.
    private static let keyCodes: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        ",": kVK_ANSI_Comma,
    ]

    /// The recorder value for a stored shortcut; nil for `"none"` (the action is off) or a value it can't show.
    static func shortcut(for value: String) -> MacShortcut? {
        let parts = value.lowercased().split(separator: "+").map(String.init)
        guard let keyName = parts.last, keyName != "none" else { return nil }
        var modifiers: MacShortcut.Modifiers = []
        for part in parts.dropLast() {
            guard let modifier = self.modifierNames.first(where: { $0.1 == part })?.0 else { return nil }
            modifiers.insert(modifier)
        }
        let key: MacShortcut.Key
        switch keyName {
        case "left": key = self.leftArrow
        case "right": key = self.rightArrow
        default:
            guard keyName.count == 1, let character = keyName.first, let code = self.keyCodes[character] else {
                return nil
            }
            key = MacShortcut.Key(code: UInt16(code), name: keyName.uppercased())
        }
        return MacShortcut(key, modifiers: modifiers)
    }

    /// The stored form of a recorded shortcut: `"none"` when cleared, nil when the key isn't one the switcher reads.
    /// Keys are named by the character they type, as the status menu matches them.
    static func value(for shortcut: MacShortcut?) -> String? {
        guard let shortcut else { return "none" }
        let key: String
        switch Int(shortcut.key.code) {
        case kVK_LeftArrow: key = "left"
        case kVK_RightArrow: key = "right"
        default:
            let name = shortcut.key.name.lowercased()
            guard name.count == 1, let character = name.first, character.isASCII,
                  character.isLetter || character.isNumber || character == ","
            else { return nil }
            key = name
        }
        let modifiers = self.modifierNames.filter { shortcut.modifiers.contains($0.0) }.map(\.1)
        return (modifiers + [key]).joined(separator: "+")
    }

    /// The full shortcut map with `shortcut` assigned to `action`, validated by `ProviderSwitcherShortcuts`; or why
    /// it can't be assigned. Clearing an action (`nil`) always succeeds.
    static func assigning(
        _ shortcut: MacShortcut?,
        to action: String,
        in current: [String: String]) -> Result<[String: String], Issue>
    {
        guard let value = self.value(for: shortcut) else { return .failure(.unsupportedKey) }
        let display = shortcut?.displayString ?? ""
        guard let normalized = try? ProviderSwitcherShortcuts.normalized(value) else {
            return .failure(.reserved(display))
        }
        if normalized != "none",
           let other = ProviderSwitcherShortcuts.actions.first(where: { $0 != action && current[$0] == normalized })
        {
            return .failure(.duplicate(action: other))
        }
        var updated = current
        updated[action] = normalized
        guard let validated = try? ProviderSwitcherShortcuts.validated(updated) else {
            return .failure(.reserved(display))
        }
        return .success(validated)
    }

    /// The row title for an action: "Previous provider", "Next provider" or "Select position N".
    static func label(for action: String) -> String {
        switch action {
        case "previous": L("Previous provider")
        case "next": L("Next provider")
        default: L("Select position %@", String(action.dropFirst("select".count)))
        }
    }

    static func message(for issue: Issue) -> String {
        switch issue {
        case .unsupportedKey: L("shortcut_issue_unsupported_key")
        case let .reserved(shortcut): L("shortcut_issue_reserved", shortcut)
        case let .duplicate(action): L("shortcut_issue_duplicate", self.label(for: action))
        }
    }
}
