//
//  MouseAction.swift
//  MouseForge
//
//  The protocol every library action conforms to, plus the reusable
//  action types (keyboard shortcut, media key, custom code). To add an
//  action: give it an ActionID and add one entry to ActionLibrary.all.
//

import Foundation

enum ActionCategory: String, CaseIterable, Identifiable, Sendable {
    case navigation, windowDesktop, editing, media, system, launch, custom, special

    var id: String { rawValue }

    var title: String {
        switch self {
        case .navigation: return "Navigation"
        case .windowDesktop: return "Window & Desktop"
        case .editing: return "Editing"
        case .media: return "Media"
        case .system: return "System"
        case .launch: return "Launch"
        case .custom: return "Custom"
        case .special: return "Special"
        }
    }
}

/// Extra input an action needs from the user.
enum ActionParameter: Equatable, Sendable {
    case none
    case shortcut
    case text(prompt: String, multiline: Bool)
    case application
    case file
    case folder
    case url
    /// One of the user's Smart Actions (its UUID in `ActionConfig.text`).
    case smartAction
}

protocol MouseAction: Sendable {
    var id: ActionID { get }
    var name: String { get }
    /// SF Symbol name.
    var symbol: String { get }
    var category: ActionCategory { get }
    var parameter: ActionParameter { get }
    /// Extra words the search field should match.
    var keywords: [String] { get }

    /// Runs the action. Called on ActionExecutor's background queue, never
    /// on the event-tap thread; must not wait on the main thread.
    func perform(_ config: ActionConfig)
}

extension MouseAction {
    var parameter: ActionParameter { .none }
    var keywords: [String] { [] }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = ([name, category.title] + keywords).joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(query)
    }
}

/// Sends a fixed keyboard shortcut.
struct ShortcutAction: MouseAction {
    let id: ActionID
    let name: String
    let symbol: String
    let category: ActionCategory
    let combo: KeyCombo
    var keywords: [String] = []

    func perform(_ config: ActionConfig) {
        SyntheticEvents.press(combo)
    }
}

/// Sends a media / brightness key like the ones on an Apple keyboard.
struct MediaKeyAction: MouseAction {
    let id: ActionID
    let name: String
    let symbol: String
    let key: SyntheticEvents.MediaKey
    var keywords: [String] = []

    var category: ActionCategory { .media }

    func perform(_ config: ActionConfig) {
        SyntheticEvents.press(key)
    }
}

/// Anything else: runs a closure.
struct CustomAction: MouseAction {
    let id: ActionID
    let name: String
    let symbol: String
    let category: ActionCategory
    var parameter: ActionParameter = .none
    var keywords: [String] = []
    let run: @Sendable (ActionConfig) -> Void

    func perform(_ config: ActionConfig) {
        run(config)
    }
}
