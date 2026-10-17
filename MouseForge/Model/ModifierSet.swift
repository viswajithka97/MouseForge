//
//  ModifierSet.swift
//  MouseForge
//
//  The four modifier keys MouseForge cares about (⌃ ⌥ ⇧ ⌘), stored as a
//  small bit set. Caps Lock and fn are deliberately ignored so they never
//  stop a binding from matching.
//

import AppKit
import CoreGraphics

struct ModifierSet: OptionSet, Hashable, Codable, Sendable {
    let rawValue: UInt8

    static let control = ModifierSet(rawValue: 1 << 0)
    static let option = ModifierSet(rawValue: 1 << 1)
    static let shift = ModifierSet(rawValue: 1 << 2)
    static let command = ModifierSet(rawValue: 1 << 3)

    /// In the order macOS displays them.
    static let ordered: [ModifierSet] = [.control, .option, .shift, .command]

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(_ flags: CGEventFlags) {
        var set: ModifierSet = []
        if flags.contains(.maskControl) { set.insert(.control) }
        if flags.contains(.maskAlternate) { set.insert(.option) }
        if flags.contains(.maskShift) { set.insert(.shift) }
        if flags.contains(.maskCommand) { set.insert(.command) }
        self = set
    }

    init(_ flags: NSEvent.ModifierFlags) {
        var set: ModifierSet = []
        if flags.contains(.control) { set.insert(.control) }
        if flags.contains(.option) { set.insert(.option) }
        if flags.contains(.shift) { set.insert(.shift) }
        if flags.contains(.command) { set.insert(.command) }
        self = set
    }

    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }

    /// e.g. "⌃⇧⌘"
    var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }

    var name: String {
        switch self {
        case .control: return "Control"
        case .option: return "Option"
        case .shift: return "Shift"
        case .command: return "Command"
        default: return symbols
        }
    }

    /// Virtual key code of the left-hand key, used when we post the
    /// modifier key itself (needed for things like ⌘-Tab).
    var leftKeyCode: CGKeyCode? {
        switch self {
        case .control: return 0x3B
        case .option: return 0x3A
        case .shift: return 0x38
        case .command: return 0x37
        default: return nil
        }
    }
}
