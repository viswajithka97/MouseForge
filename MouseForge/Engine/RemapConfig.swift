//
//  RemapConfig.swift
//  MouseForge
//
//  An immutable snapshot of "what should each button do right now", built
//  on the main thread whenever settings or the frontmost app change, and
//  read by the event-tap thread. Precomputing it means the tap thread only
//  does a dictionary lookup per click.
//

import Foundation

/// Everything bound to one button for one modifier combination, after
/// profile inheritance. `nil` means "not remapped".
struct ButtonBindings: Equatable, Sendable {
    var click: ActionConfig?
    var doubleClick: ActionConfig?
    var tripleClick: ActionConfig?
    var hold: ActionConfig?
    var gestures: [GestureDirection: ActionConfig] = [:]

    var hasAnyAction: Bool {
        click != nil || doubleClick != nil || tripleClick != nil || hold != nil || hasGestures
    }

    var hasGestures: Bool { !gestures.isEmpty }

    /// Only a Click action: nothing to wait for, so it can fire the moment
    /// the button goes down.
    var isClickOnly: Bool {
        click != nil && doubleClick == nil && tripleClick == nil && hold == nil && gestures.isEmpty
    }

    func action(forClickCount count: Int) -> ActionConfig? {
        switch count {
        case 1: return click
        case 2: return doubleClick
        case 3: return tripleClick
        default: return nil
        }
    }

    /// True if waiting for another click could still lead to a different
    /// action. When false, the click fires immediately on release.
    func expectsMoreClicks(after count: Int) -> Bool {
        switch count {
        case 1: return doubleClick != nil || tripleClick != nil
        case 2: return tripleClick != nil
        default: return false
        }
    }

    fileprivate mutating func set(_ action: ActionConfig, for kind: TriggerKind) {
        switch kind {
        case .click: click = action
        case .doubleClick: doubleClick = action
        case .tripleClick: tripleClick = action
        case .hold: hold = action
        case .gestureUp, .gestureDown, .gestureLeft, .gestureRight:
            if let direction = kind.gestureDirection { gestures[direction] = action }
        }
    }
}

struct RemapConfig: Sendable {
    struct Chord: Hashable, Sendable {
        var button: MouseButtonNumber
        var modifiers: ModifierSet
    }

    var enabled: Bool
    var allowPrimaryButtonRemap: Bool
    var doubleClickInterval: TimeInterval
    var holdThreshold: TimeInterval
    var gestureThreshold: Double = 50
    var gestureRepeats = false
    var gestureFreezesPointer = true
    var gestureHints = true
    var scroll = ScrollSettings()
    var thumbWheel = ThumbWheelSettings()
    var table: [Chord: ButtonBindings]

    /// Nothing remapped; used before settings load.
    static let passThrough = RemapConfig(
        enabled: false, allowPrimaryButtonRemap: false,
        doubleClickInterval: 0.3, holdThreshold: 0.45, table: [:]
    )

    init(
        enabled: Bool, allowPrimaryButtonRemap: Bool,
        doubleClickInterval: TimeInterval, holdThreshold: TimeInterval,
        table: [Chord: ButtonBindings]
    ) {
        self.enabled = enabled
        self.allowPrimaryButtonRemap = allowPrimaryButtonRemap
        self.doubleClickInterval = doubleClickInterval
        self.holdThreshold = holdThreshold
        self.table = table
    }

    /// Builds the lookup table from resolved (already inherited) bindings.
    init(general: GeneralSettings, bindings: [TriggerKey: ActionConfig]) {
        var table: [Chord: ButtonBindings] = [:]
        for (trigger, action) in bindings where !action.isDefaultBehavior {
            table[Chord(button: trigger.button, modifiers: trigger.modifiers), default: ButtonBindings()]
                .set(action, for: trigger.kind)
        }
        self.init(
            enabled: general.remappingEnabled,
            allowPrimaryButtonRemap: general.allowPrimaryButtonRemap,
            doubleClickInterval: general.doubleClickInterval,
            holdThreshold: general.holdThreshold,
            table: table
        )
        gestureThreshold = general.gestureThreshold
        gestureRepeats = general.gestureRepeats
        gestureFreezesPointer = general.gestureFreezesPointer
        gestureHints = general.gestureHints
    }

    /// Exact modifier match first. If the user holds modifiers that have no
    /// bindings of their own, fall back to the plain bindings so, e.g.,
    /// ⇧ + Back still goes back.
    func bindings(button: MouseButtonNumber, modifiers: ModifierSet) -> ButtonBindings? {
        if let exact = table[Chord(button: button, modifiers: modifiers)] { return exact }
        guard !modifiers.isEmpty else { return nil }
        return table[Chord(button: button, modifiers: [])]
    }
}
