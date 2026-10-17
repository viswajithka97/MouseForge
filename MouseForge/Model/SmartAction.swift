//
//  SmartAction.swift
//  MouseForge
//
//  A Smart Action is a named macro: a list of steps run one after another.
//  Each step is either any library action (which covers typing text and
//  opening apps, URLs, and files) or a pause.
//

import Foundation

struct SmartStep: Identifiable, Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case action
        case delay
    }

    var id = UUID()
    var kind: Kind
    var action: ActionConfig?
    /// Seconds, for `.delay`.
    var delay: Double?

    static let delayRange: ClosedRange<Double> = 0.05...60

    static func action(_ action: ActionConfig) -> SmartStep {
        SmartStep(kind: .action, action: action)
    }

    static func delay(_ seconds: Double) -> SmartStep {
        SmartStep(kind: .delay, delay: seconds)
    }

    var summary: String {
        switch kind {
        case .delay:
            return String(format: "Wait %.2g s", delay ?? 0)
        case .action:
            return action.map(ActionLibrary.displayName(for:)) ?? "Choose an action"
        }
    }
}

struct SmartAction: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var name: String
    var symbol: String = "wand.and.stars"
    var steps: [SmartStep] = []

    /// The ActionConfig that runs this Smart Action from a button, gesture,
    /// or ring slot.
    var actionConfig: ActionConfig {
        ActionConfig(.smartAction, text: id.uuidString)
    }

    static let symbolChoices = [
        "wand.and.stars", "bolt.fill", "sparkles", "star.fill", "flag.fill", "bookmark.fill",
        "briefcase.fill", "cup.and.saucer.fill", "music.note", "video.fill", "envelope.fill",
        "doc.text.fill", "globe", "terminal.fill", "camera.fill", "moon.fill",
    ]
}

/// Thread-safe snapshot of the user's Smart Actions, readable from the
/// action queue (for running) and the UI (for names).
final class SmartActionRegistry: @unchecked Sendable {
    static let shared = SmartActionRegistry()

    private let lock = NSLock()
    private var byID: [UUID: SmartAction] = [:]

    func update(_ actions: [SmartAction]) {
        lock.lock()
        byID = Dictionary(actions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        lock.unlock()
    }

    func smartAction(for config: ActionConfig) -> SmartAction? {
        guard let text = config.text, let id = UUID(uuidString: text) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return byID[id]
    }
}

enum SmartActionTemplates {
    static var all: [SmartAction] {
        [
            SmartAction(name: "Focus Session", symbol: "moon.fill", steps: [
                .action(ActionConfig(.doNotDisturb)),
                .action(ActionConfig(.openApp, text: "/System/Applications/Music.app")),
                .delay(1.5),
                .action(ActionConfig(.playPause)),
            ]),
            SmartAction(name: "Quick Note", symbol: "doc.text.fill", steps: [
                .action(ActionConfig(.openApp, text: "/System/Applications/Notes.app")),
                .delay(1),
                .action(.shortcut("New Note", KeyCombo(0x2D, .command), symbol: "square.and.pencil")),
                .delay(0.3),
                .action(ActionConfig(.typeText, text: "Note: ")),
            ]),
            SmartAction(name: "Web Search", symbol: "globe", steps: [
                .action(ActionConfig(.openURL, text: "https://duckduckgo.com")),
            ]),
            SmartAction(name: "Copy & Search", symbol: "magnifyingglass", steps: [
                .action(ActionConfig(.copy)),
                .delay(0.2),
                .action(ActionConfig(.spotlight)),
                .delay(0.4),
                .action(ActionConfig(.paste)),
            ]),
            SmartAction(name: "Screenshot to Clipboard", symbol: "camera.fill", steps: [
                .action(.shortcut("Copy Area Screenshot", KeyCombo(0x15, [.control, .shift, .command]), symbol: "camera.viewfinder")),
            ]),
            SmartAction(name: "Email Sign-off", symbol: "envelope.fill", steps: [
                .action(ActionConfig(.typeText, text: "\n\nBest regards,\n")),
            ]),
            SmartAction(name: "Clean Desktop View", symbol: "sparkles", steps: [
                .action(ActionConfig(.hideApp)),
                .delay(0.3),
                .action(ActionConfig(.showDesktop)),
            ]),
        ]
    }

    /// A copy with fresh IDs, ready to add to the user's list.
    static func instantiate(_ template: SmartAction) -> SmartAction {
        var copy = template
        copy.id = UUID()
        copy.steps = copy.steps.map { step in
            var step = step
            step.id = UUID()
            return step
        }
        return copy
    }
}
