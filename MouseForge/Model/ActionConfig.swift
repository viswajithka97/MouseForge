//
//  ActionConfig.swift
//  MouseForge
//
//  What a trigger is bound to: an action from the library plus whatever
//  extra data that action needs (a recorded shortcut, a URL, a script…).
//  This is the part that gets saved to JSON.
//

import Foundation

/// Stable identifier of a library action. Saved in settings, so existing
/// raw values must never change.
struct ActionID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}

struct ActionConfig: Hashable, Codable, Sendable {
    var actionID: ActionID
    /// For "Keyboard Shortcut".
    var shortcut: KeyCombo?
    /// Text snippet, script source, URL, file/app path, or Shortcuts name,
    /// depending on the action.
    var text: String?
    /// Optional custom name shown instead of the generated one (e.g.
    /// "History" for a ⌘Y shortcut in an Actions Ring slot).
    var label: String?
    /// Optional SF Symbol shown instead of the action's own icon.
    var symbol: String?

    init(_ actionID: ActionID, shortcut: KeyCombo? = nil, text: String? = nil, label: String? = nil, symbol: String? = nil) {
        self.actionID = actionID
        self.shortcut = shortcut
        self.text = text
        self.label = label
        self.symbol = symbol
    }

    /// A keyboard shortcut with a friendly name and icon.
    static func shortcut(_ name: String, _ combo: KeyCombo, symbol: String? = nil) -> ActionConfig {
        ActionConfig(.keyboardShortcut, shortcut: combo, label: name, symbol: symbol)
    }

    /// "Default behavior" means "act as if MouseForge weren't here". In an
    /// app profile it is still an explicit override (it hides the global
    /// binding), but the engine treats it as unbound.
    var isDefaultBehavior: Bool { actionID == .defaultBehavior }
}
