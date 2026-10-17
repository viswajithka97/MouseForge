//
//  KeyCombo.swift
//  MouseForge
//
//  A keyboard shortcut: one key plus modifiers. Stored by virtual key code
//  (the physical key position) so it keeps working if the user switches
//  keyboard layouts; the display name follows the current layout.
//

import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct KeyCombo: Hashable, Codable, Sendable {
    var keyCode: UInt16
    var modifiers: ModifierSet

    init(_ keyCode: Int, _ modifiers: ModifierSet = []) {
        self.keyCode = UInt16(keyCode)
        self.modifiers = modifiers
    }

    /// e.g. "⇧⌘T"
    var displayString: String {
        modifiers.symbols + KeyNames.name(for: keyCode)
    }
}

/// Human-readable names for virtual key codes.
enum KeyNames {
    private static let special: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_ANSI_KeypadEnter: "⌤",
        kVK_ANSI_KeypadClear: "⌧", kVK_Help: "Help",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func name(for keyCode: UInt16) -> String {
        if let name = special[Int(keyCode)] { return name }
        if let character = character(for: keyCode), !character.isEmpty {
            return character.uppercased()
        }
        return "Key \(keyCode)"
    }

    /// Asks the current keyboard layout which character a key produces with
    /// no modifiers (so ⌘ shortcuts read "⌘Z" on QWERTY and "⌘Y" on QWERTZ
    /// for the same physical key, just like macOS menus).
    private static func character(for keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data

        return layoutData.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
