//
//  Trigger.swift
//  MouseForge
//
//  What the user does with a button: click it once, twice, three times, or
//  hold it down, optionally while holding modifier keys.
//

import Foundation

/// 1-based, the way users count: 1 = left, 2 = right, 3 = middle,
/// 4 = back, 5 = forward, 6+ = extra buttons.
typealias MouseButtonNumber = Int

enum MouseButtons {
    static let left = 1
    static let right = 2
    static let middle = 3
    static let back = 4
    static let forward = 5

    static func isPrimary(_ button: MouseButtonNumber) -> Bool {
        button == left || button == right
    }

    static func name(_ button: MouseButtonNumber) -> String {
        if let cid = LogitechButtons.controlID(for: button) {
            return LogitechButtons.name(cid)
        }
        switch button {
        case left: return "Left Button"
        case right: return "Right Button"
        case middle: return "Middle Button"
        case back: return "Back Button"
        case forward: return "Forward Button"
        default: return "Button \(button)"
        }
    }
}

enum TriggerKind: String, Codable, CaseIterable, Sendable {
    case click
    case doubleClick
    case tripleClick
    case hold
    /// Hold the button and move the mouse (click-and-drag gesture).
    case gestureUp
    case gestureDown
    case gestureLeft
    case gestureRight

    var title: String {
        switch self {
        case .click: return "Click"
        case .doubleClick: return "Double Click"
        case .tripleClick: return "Triple Click"
        case .hold: return "Hold"
        case .gestureUp: return "Gesture Up"
        case .gestureDown: return "Gesture Down"
        case .gestureLeft: return "Gesture Left"
        case .gestureRight: return "Gesture Right"
        }
    }

    /// Click, double, triple, hold: the kinds offered with modifiers.
    static let pressKinds: [TriggerKind] = [.click, .doubleClick, .tripleClick, .hold]

    var gestureDirection: GestureDirection? {
        switch self {
        case .gestureUp: return .up
        case .gestureDown: return .down
        case .gestureLeft: return .left
        case .gestureRight: return .right
        default: return nil
        }
    }
}

enum GestureDirection: String, Codable, CaseIterable, Sendable {
    case up, down, left, right

    var triggerKind: TriggerKind {
        switch self {
        case .up: return .gestureUp
        case .down: return .gestureDown
        case .left: return .gestureLeft
        case .right: return .gestureRight
        }
    }

    var title: String { rawValue.capitalized }

    var arrowSymbol: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }
}

/// Identifies one bindable trigger, e.g. "⇧ + double-click Button 4".
struct TriggerKey: Hashable, Codable, Sendable {
    var button: MouseButtonNumber
    var kind: TriggerKind
    var modifiers: ModifierSet

    init(button: MouseButtonNumber, kind: TriggerKind, modifiers: ModifierSet = []) {
        self.button = button
        self.kind = kind
        self.modifiers = modifiers
    }

    var displayName: String {
        let prefix = modifiers.isEmpty ? "" : modifiers.symbols + " "
        return "\(prefix)\(kind.title) – \(MouseButtons.name(button))"
    }
}

/// Logitech controls diverted over HID++ (like the gesture button) become
/// "virtual" button numbers so they work with every trigger, gesture, and
/// profile, just like ordinary buttons.
enum LogitechButtons {
    static let base = 1000
    static let gestureButtonCID: UInt16 = 0x00C3

    static func buttonNumber(for cid: UInt16) -> MouseButtonNumber { base + Int(cid) }

    static func controlID(for button: MouseButtonNumber) -> UInt16? {
        guard button >= base, button - base <= Int(UInt16.max) else { return nil }
        return UInt16(button - base)
    }

    static func isVirtual(_ button: MouseButtonNumber) -> Bool { button >= base }

    static func name(_ cid: UInt16) -> String {
        ControlInfo(cid: cid, taskID: 0, flags: 0).name
    }
}
