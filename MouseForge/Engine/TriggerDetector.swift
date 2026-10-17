//
//  TriggerDetector.swift
//  MouseForge
//
//  Turns raw button down/up events into triggers (click, double click,
//  triple click, hold). Runs entirely on the event-tap thread: events and
//  timers arrive on the same thread, so no locks are needed here.
//
//  For a remapped button the real down/up events are swallowed and an
//  action fires instead. If the user turns out to do something that isn't
//  bound (say, a single click when only double click is remapped), the
//  original click is replayed so the button still works normally.
//

import CoreGraphics
import Foundation

/// A cancellable one-shot timer. Abstracted so tests can control time.
protocol TriggerTimer: AnyObject {
    func cancel()
}

protocol TriggerScheduler {
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> TriggerTimer
}

final class TriggerDetector {
    enum Decision: Equatable {
        /// Let the original event continue to apps.
        case pass
        /// Drop the original event; MouseForge handles it.
        case swallow
    }

    enum DragDecision: Equatable {
        case pass
        /// The button's down was swallowed, so turn the drag into a plain
        /// mouse move (apps would otherwise see a drag with no press).
        case convertToMove
        /// Drop the movement (the pointer is frozen during a gesture).
        case swallow
    }

    struct Output {
        /// Run a bound action.
        var perform: (ActionConfig) -> Void
        /// Re-post `count` ordinary clicks of `button`.
        var replayClicks: (_ button: MouseButtonNumber, _ count: Int) -> Void
        /// Re-post just a button-down (the user started dragging, so the
        /// release that follows is passed through untouched).
        var replayDown: (_ button: MouseButtonNumber) -> Void
        /// A trigger was recognized (for the live test area). `action` is
        /// nil when the original click was replayed.
        var recognized: (_ trigger: TriggerKey, _ action: ActionConfig?) -> Void = { _, _ in }
        /// A "while held" action (the Actions Ring) started: it stays
        /// active until `endHeld` reports the release (or a cancel).
        var beginHeld: (_ button: MouseButtonNumber, _ action: ActionConfig) -> Void = { _, _ in }
        var endHeld: (_ button: MouseButtonNumber, _ cancelled: Bool) -> Void = { _, _ in }
        /// Hold the pointer still (true) or release it (false).
        var freezePointer: (Bool) -> Void = { _ in }
        /// A gesture was recognized (for the on-screen hint).
        var gesture: (_ button: MouseButtonNumber, _ direction: GestureDirection, _ action: ActionConfig?) -> Void = { _, _, _ in }
    }

    /// Actions that run for as long as the button stays down when bound
    /// to Hold, instead of firing once.
    static let heldActions: Set<ActionID> = [.actionsRing]

    /// Moving further than this while pressed means "drag", not "click".
    static let dragThreshold: CGFloat = 6

    private struct Sequence {
        let bindings: ButtonBindings
        let modifiers: ModifierSet
        let doubleClickInterval: TimeInterval
        var clickCount = 0
        var isPressed = true
        var holdFired = false
        /// A held action (see `heldActions`) is running until release.
        var heldActive = false
        /// Present when the button has gesture bindings.
        var gesture: GestureRecognizer?
        var gestureFired = false
        var gestureRepeats = false
        var pointerFrozen = false
        var downLocation: CGPoint
        var holdTimer: TriggerTimer?
        var waitTimer: TriggerTimer?

        func cancelTimers() {
            holdTimer?.cancel()
            waitTimer?.cancel()
        }
    }

    private let scheduler: TriggerScheduler
    private let config: () -> RemapConfig
    private let output: Output

    /// Buttons currently being tracked for a trigger.
    private var sequences: [MouseButtonNumber: Sequence] = [:]
    /// Buttons whose down event was passed to apps, so their up must be too.
    private var passedThrough: Set<MouseButtonNumber> = []

    init(scheduler: TriggerScheduler, config: @escaping () -> RemapConfig, output: Output) {
        self.scheduler = scheduler
        self.config = config
        self.output = output
    }

    // MARK: - Events

    func buttonDown(_ button: MouseButtonNumber, modifiers: ModifierSet, at location: CGPoint) -> Decision {
        let config = config()

        // Second or third press of a multi-click.
        if var sequence = sequences[button], !sequence.isPressed {
            sequence.waitTimer?.cancel()
            sequence.waitTimer = nil
            guard config.enabled else {
                // Kill switch hit between clicks: drop the sequence.
                sequences[button] = nil
                passedThrough.insert(button)
                return .pass
            }
            sequence.isPressed = true
            sequence.downLocation = location
            sequences[button] = sequence
            return .swallow
        }

        // A down without an up (e.g. the up was lost when the tap restarted
        // or a Logitech mouse disconnected): release the stale state fully.
        if let stale = sequences.removeValue(forKey: button) {
            release(button, stale)
        }
        passedThrough.remove(button)

        guard
            config.enabled,
            config.allowPrimaryButtonRemap || !MouseButtons.isPrimary(button),
            let bindings = config.bindings(button: button, modifiers: modifiers),
            bindings.hasAnyAction
        else {
            passedThrough.insert(button)
            return .pass
        }

        var sequence = Sequence(
            bindings: bindings, modifiers: modifiers,
            doubleClickInterval: config.doubleClickInterval, downLocation: location
        )

        // Nothing else is bound, so don't wait for the release. The middle
        // button keeps firing on release so middle-drag can still go to apps.
        if bindings.isClickOnly, button != MouseButtons.middle, let click = bindings.click {
            sequence.holdFired = true // the release is swallowed, nothing more fires
            sequences[button] = sequence
            output.recognized(TriggerKey(button: button, kind: .click, modifiers: modifiers), click)
            output.perform(click)
            return .swallow
        }
        if bindings.hold != nil {
            sequence.holdTimer = scheduler.schedule(after: config.holdThreshold) { [weak self] in
                self?.holdTimerFired(button)
            }
        }
        if bindings.hasGestures {
            sequence.gesture = GestureRecognizer(threshold: config.gestureThreshold)
            sequence.gestureRepeats = config.gestureRepeats
            if config.gestureFreezesPointer {
                sequence.pointerFrozen = true
                output.freezePointer(true)
            }
        }
        sequences[button] = sequence
        return .swallow
    }

    func buttonUp(_ button: MouseButtonNumber) -> Decision {
        if passedThrough.remove(button) != nil { return .pass }
        guard var sequence = sequences[button], sequence.isPressed else { return .pass }

        sequence.holdTimer?.cancel()
        sequence.holdTimer = nil
        if sequence.pointerFrozen {
            sequence.pointerFrozen = false
            output.freezePointer(false)
        }
        if sequence.holdFired || sequence.gestureFired {
            sequences[button] = nil
            if sequence.heldActive { output.endHeld(button, false) }
            return .swallow
        }

        sequence.isPressed = false
        sequence.clickCount += 1

        if sequence.bindings.expectsMoreClicks(after: sequence.clickCount) {
            sequence.waitTimer = scheduler.schedule(after: sequence.doubleClickInterval) { [weak self] in
                self?.waitTimerFired(button)
            }
            sequences[button] = sequence
        } else {
            sequences[button] = nil
            if config().enabled {
                finish(button, sequence: sequence)
            }
        }
        return .swallow
    }

    /// `delta` is the movement of this event (screen points, y down).
    func dragged(_ button: MouseButtonNumber, to location: CGPoint, delta: CGVector = .zero) -> DragDecision {
        guard var sequence = sequences[button], sequence.isPressed else { return .pass }
        let moved: DragDecision = sequence.pointerFrozen ? .swallow : .convertToMove
        if sequence.holdFired || sequence.clickCount > 0 { return moved }
        // A diverted Logitech control has no native drag to hand back, so
        // movement never cancels its click or hold.
        if sequence.gesture == nil, LogitechButtons.isVirtual(button) { return moved }

        if var recognizer = sequence.gesture {
            if sequence.gestureFired && !sequence.gestureRepeats { return moved }
            if let direction = recognizer.add(dx: delta.dx, dy: delta.dy) {
                sequence.gestureFired = true
                sequence.holdTimer?.cancel()
                sequence.holdTimer = nil
                let action = sequence.bindings.gestures[direction]
                if config().enabled {
                    output.recognized(TriggerKey(button: button, kind: direction.triggerKind, modifiers: sequence.modifiers), action)
                    output.gesture(button, direction, action)
                    if let action { output.perform(action) }
                }
            }
            sequence.gesture = recognizer
            sequences[button] = sequence
            return moved
        }

        let dx = location.x - sequence.downLocation.x
        let dy = location.y - sequence.downLocation.y
        guard dx * dx + dy * dy > Self.dragThreshold * Self.dragThreshold else { return .convertToMove }

        // The user is dragging (e.g. middle-drag to pan), not clicking: give
        // the press back to the app and stop tracking.
        sequence.cancelTimers()
        sequences[button] = nil
        passedThrough.insert(button)
        output.replayDown(button)
        return .convertToMove
    }

    /// Forget everything, e.g. when the tap restarts.
    func reset() {
        for (button, sequence) in sequences {
            release(button, sequence)
        }
        sequences.removeAll()
        passedThrough.removeAll()
    }

    /// Stops timers, unfreezes the pointer, and cancels a held action.
    private func release(_ button: MouseButtonNumber, _ sequence: Sequence) {
        sequence.cancelTimers()
        if sequence.heldActive { output.endHeld(button, true) }
        if sequence.pointerFrozen { output.freezePointer(false) }
    }

    // MARK: - Timers

    private func holdTimerFired(_ button: MouseButtonNumber) {
        guard var sequence = sequences[button], sequence.isPressed, !sequence.holdFired,
              let hold = sequence.bindings.hold
        else { return }
        sequence.holdTimer = nil
        sequence.holdFired = true
        guard config().enabled else {
            sequences[button] = sequence
            return
        }
        output.recognized(TriggerKey(button: button, kind: .hold, modifiers: sequence.modifiers), hold)
        if Self.heldActions.contains(hold.actionID) {
            sequence.heldActive = true
            // The ring is chosen by pointing, so the pointer must move.
            if sequence.pointerFrozen {
                sequence.pointerFrozen = false
                output.freezePointer(false)
            }
            sequences[button] = sequence
            output.beginHeld(button, hold)
        } else {
            sequences[button] = sequence
            output.perform(hold)
        }
    }

    private func waitTimerFired(_ button: MouseButtonNumber) {
        guard let sequence = sequences[button], !sequence.isPressed else { return }
        sequences[button] = nil
        guard config().enabled else { return }
        finish(button, sequence: sequence)
    }

    private func finish(_ button: MouseButtonNumber, sequence: Sequence) {
        let bindings = sequence.bindings
        let clicks = sequence.clickCount
        let kind: TriggerKind = clicks >= 3 ? .tripleClick : clicks == 2 ? .doubleClick : .click
        let trigger = TriggerKey(button: button, kind: kind, modifiers: sequence.modifiers)
        if let action = bindings.action(forClickCount: clicks) {
            output.recognized(trigger, action)
            output.perform(action)
        } else if let click = bindings.click {
            // e.g. a double click when only single and triple are bound:
            // treat it as that many single clicks.
            for _ in 0..<clicks {
                output.recognized(TriggerKey(button: button, kind: .click, modifiers: sequence.modifiers), click)
                output.perform(click)
            }
        } else {
            output.recognized(trigger, nil)
            output.replayClicks(button, clicks)
        }
    }
}

/// Schedules timers on the run loop of the thread that calls `schedule`
/// (the event-tap thread), so timer callbacks never race with events.
final class RunLoopTriggerScheduler: TriggerScheduler {
    private final class Timer: TriggerTimer {
        let timer: CFRunLoopTimer
        init(_ timer: CFRunLoopTimer) { self.timer = timer }
        func cancel() { CFRunLoopTimerInvalidate(timer) }
    }

    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> TriggerTimer {
        let timer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0
        ) { _ in block() }!
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
        return Timer(timer)
    }
}
