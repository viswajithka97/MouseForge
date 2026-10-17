//
//  EventTapEngine.swift
//  MouseForge
//
//  Installs a Quartz event tap (CGEventTap) that sees every mouse button,
//  drag, scroll, and key-down event before apps do. The tap lives on its own
//  high-priority thread so a busy main thread (UI work) can never delay
//  mouse input.
//
//  Button events go through TriggerDetector, which may swallow them and
//  run an action instead; scroll events go through ScrollEngine. Logitech
//  controls diverted over HID++ are injected as virtual buttons. Also
//  handles the ⌃⌥⌘M kill switch and Actions Ring input.
//

import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

final class EventTapEngine: @unchecked Sendable {
    enum StartError: Error {
        /// `CGEvent.tapCreate` returned nil. Almost always means the
        /// Accessibility permission is missing (or stale after a rebuild).
        case tapCreationFailed
    }

    let log = InputEventLog()
    let activity = ActivityLog()
    let scroll = ScrollEngine()

    /// Called on the main thread after the kill switch flips remapping.
    var onKillSwitch: ((_ remappingEnabled: Bool) -> Void)?
    /// Called on the main thread the first time a button number ≥ 6 is seen.
    var onNewExtraButton: ((MouseButtonNumber) -> Void)?
    /// Called on the main thread for Actions Ring input.
    var onRingInput: ((RingInput) -> Void)?
    /// Called on the main thread when a gesture fires.
    var onGesture: ((_ direction: GestureDirection, _ action: ActionConfig?, _ showHint: Bool) -> Void)?

    enum RingCaptureMode: Sendable {
        case none
        /// Opened by holding a button; selection happens on release.
        case held
        /// Opened by a click; the next click selects.
        case sticky
    }

    enum RingInput: Sendable {
        case heldBegan(MouseButtonNumber)
        case heldEnded(cancelled: Bool)
        case escape
        case click(secondary: Bool)
    }

    private let logger = Logger(subsystem: "com.mouse.forge.MouseForge", category: "EventTap")

    /// Written by the main thread, read by the tap thread on every press.
    private let config = OSAllocatedUnfairLock(initialState: RemapConfig.passThrough)
    private let ringCapture = OSAllocatedUnfairLock(initialState: RingCaptureMode.none)

    // Written on the thread that calls start/stop (main), read by the tap
    // thread only after it has been set up, so no extra locking is needed.
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    // Only touched on the tap thread.
    private var detector: TriggerDetector?
    private var seenExtraButtons: Set<MouseButtonNumber> = []
    /// Releases to swallow because their press was used by the ring.
    private var swallowedUps: Set<MouseButtonNumber> = []
    /// Virtual (diverted Logitech) buttons currently held.
    private var pressedVirtual: Set<MouseButtonNumber> = []

    var isRunning: Bool { tap != nil }

    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved,
            .scrollWheel,
            .keyDown,
        ]
        return types.reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }
    }()

    /// Swap in new bindings. Safe to call from any thread; takes effect on
    /// the next button press.
    func update(_ newConfig: RemapConfig) {
        config.withLock { $0 = newConfig }
    }

    /// Set by the Actions Ring while it's on screen.
    func setRingCapture(_ mode: RingCaptureMode) {
        ringCapture.withLock { $0 = mode }
    }

    func setKnownExtraButtons(_ buttons: [MouseButtonNumber]) {
        // Before start() only, so the tap thread isn't running yet.
        if tap == nil { seenExtraButtons = Set(buttons) }
    }

    func start() throws {
        guard tap == nil else { return }

        // `.defaultTap` (not `.listenOnly`) so we can modify or swallow
        // events. It requires the Accessibility permission.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("CGEvent.tapCreate failed – is Accessibility permission granted?")
            throw StartError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.tap = tap
        self.runLoopSource = source
        self.detector = makeDetector()
        swallowedUps.removeAll()
        pressedVirtual.removeAll()
        scroll.activity = activity

        // The thread signals once its run loop exists so stop() can always
        // find it, even if called immediately after start().
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun() // Returns when stop() calls CFRunLoopStop.
        }
        thread.name = "MouseForge.EventTap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        ready.wait()

        logger.info("Event tap started")
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let tapRunLoop, let runLoopSource {
            CFRunLoopRemoveSource(tapRunLoop, runLoopSource, .commonModes)
            CFRunLoopStop(tapRunLoop)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
        // Never leave the pointer frozen by an unfinished gesture.
        CGAssociateMouseAndMouseCursorPosition(1)
        logger.info("Event tap stopped")
    }

    private func makeDetector() -> TriggerDetector {
        TriggerDetector(
            scheduler: RunLoopTriggerScheduler(),
            config: { [config] in config.withLock { $0 } },
            output: TriggerDetector.Output(
                perform: { ActionExecutor.shared.perform($0) },
                // Virtual buttons have no native click to give back.
                replayClicks: { button, count in
                    guard !LogitechButtons.isVirtual(button) else { return }
                    SyntheticEvents.click(button: button, count: count)
                },
                replayDown: { button in
                    guard !LogitechButtons.isVirtual(button) else { return }
                    SyntheticEvents.buttonDown(button)
                },
                recognized: { [activity] trigger, action in activity.record(trigger: trigger, action: action) },
                beginHeld: { [weak self] button, _ in self?.sendRing(.heldBegan(button)) },
                endHeld: { [weak self] _, cancelled in self?.sendRing(.heldEnded(cancelled: cancelled)) },
                freezePointer: { frozen in
                    // While frozen, the mouse still reports movement deltas
                    // but the visible pointer stays put.
                    CGAssociateMouseAndMouseCursorPosition(frozen ? 0 : 1)
                },
                gesture: { [weak self] _, direction, action in
                    guard let self else { return }
                    let showHint = self.config.withLock { $0.gestureHints }
                    let callback = self.onGesture
                    DispatchQueue.main.async { callback?(direction, action, showHint) }
                }
            )
        )
    }

    // MARK: - Injected input (from HID++)

    /// A diverted Logitech control went down or up. Runs on the tap thread
    /// so it shares the trigger detector with real buttons.
    func injectVirtualButton(_ button: MouseButtonNumber, down: Bool) {
        onTapThread { [weak self] in
            guard let self, let detector = self.detector else { return }
            if down {
                self.pressedVirtual.insert(button)
                self.noteButton(button)
                let flags = CGEventSource.flagsState(.combinedSessionState)
                _ = detector.buttonDown(button, modifiers: ModifierSet(flags), at: SyntheticEvents.cursorLocation)
            } else {
                self.pressedVirtual.remove(button)
                _ = detector.buttonUp(button)
            }
        }
    }

    /// Thumb-wheel rotation from a diverted Logitech thumb wheel, in
    /// notches (positive = towards the "left" action).
    func injectThumbWheel(notches: Double) {
        onTapThread { [weak self] in
            guard let self else { return }
            let config = self.config.withLock { $0 }
            guard config.enabled else { return }
            if config.thumbWheel.mode == .horizontalScroll {
                let direction: Double = config.thumbWheel.invert ? -1 : 1
                self.scroll.scrollHorizontally(pixels: notches * direction * config.thumbWheel.speed * ScrollMath.pixelsPerNotch * 0.7)
            } else {
                self.scroll.rotateThumbWheel(by: config.thumbWheel.invert ? -notches : notches, settings: config.thumbWheel)
            }
        }
    }

    private func onTapThread(_ body: @escaping () -> Void) {
        guard let runLoop = tapRunLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, body)
        CFRunLoopWakeUp(runLoop)
    }

    private func sendRing(_ input: RingInput) {
        let callback = onRingInput
        DispatchQueue.main.async { callback?(input) }
    }

    // MARK: - Tap thread

    /// Called on the tap thread for every event. Must be fast and must never
    /// block: no main-thread waits, no file I/O.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // Our own synthetic events (replayed clicks, shortcuts) go straight through.
        if SyntheticEvents.isSynthetic(event) { return pass }

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps that are too slow or when secure input
            // toggles. Turn ourselves straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            detector?.reset()
            swallowedUps.removeAll()
            pressedVirtual.removeAll()
            let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
            logger.warning("Event tap disabled by \(reason, privacy: .public); re-enabled")
            log.append(.tapReEnabled(reason: reason), modifiers: [])
            return pass

        case .keyDown:
            return handleKeyDown(event) ? nil : pass

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let button = buttonNumber(event)
            // A new press proves any release we were waiting to swallow was lost.
            swallowedUps.remove(button)
            if type != .otherMouseDown, ringCapture.withLock({ $0 }) != .none {
                // A click while the ring is open picks a slot (or cancels).
                swallowedUps.insert(button)
                sendRing(.click(secondary: type == .rightMouseDown))
                return nil
            }
            let clicks = Int(event.getIntegerValueField(.mouseEventClickState))
            log.append(.buttonDown(button: button, clickCount: clicks), modifiers: event.flags)
            noteButton(button)
            let decision = detector?.buttonDown(button, modifiers: ModifierSet(event.flags), at: event.location) ?? .pass
            return decision == .swallow ? nil : pass

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let button = buttonNumber(event)
            if swallowedUps.remove(button) != nil { return nil }
            log.append(.buttonUp(button: button), modifiers: event.flags)
            let decision = detector?.buttonUp(button) ?? .pass
            return decision == .swallow ? nil : pass

        case .mouseMoved:
            // Movement while a virtual button is held drives its gestures.
            guard !pressedVirtual.isEmpty, let detector else { return pass }
            let delta = CGVector(
                dx: event.getDoubleValueField(.mouseEventDeltaX),
                dy: event.getDoubleValueField(.mouseEventDeltaY)
            )
            var swallow = false
            for button in pressedVirtual where detector.dragged(button, to: event.location, delta: delta) == .swallow {
                swallow = true
            }
            return swallow ? nil : pass

        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let delta = CGVector(
                dx: event.getDoubleValueField(.mouseEventDeltaX),
                dy: event.getDoubleValueField(.mouseEventDeltaY)
            )
            switch detector?.dragged(buttonNumber(event), to: event.location, delta: delta) ?? .pass {
            case .pass: return pass
            case .swallow: return nil
            case .convertToMove:
                event.type = .mouseMoved
                return pass
            }

        case .scrollWheel:
            if log.isCapturing {
                let dy = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
                let dx = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
                let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
                let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
                let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
                log.append(
                    .scroll(deltaY: dy, deltaX: dx, isContinuous: continuous, phase: phase, momentumPhase: momentum),
                    modifiers: event.flags
                )
            }
            let config = config.withLock { $0 }
            guard let result = scroll.handle(event, settings: config.scroll, thumbWheel: config.thumbWheel, enabled: config.enabled) else {
                return nil
            }
            return Unmanaged.passUnretained(result)

        default:
            return pass
        }
    }

    private func buttonNumber(_ event: CGEvent) -> MouseButtonNumber {
        Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
    }

    private func noteButton(_ button: MouseButtonNumber) {
        guard button > MouseButtons.forward, !LogitechButtons.isVirtual(button),
              seenExtraButtons.insert(button).inserted else { return }
        let callback = onNewExtraButton
        DispatchQueue.main.async { callback?(button) }
    }

    /// ⌃⌥⌘M toggles remapping; Esc closes the Actions Ring. Returns true
    /// if the key was consumed.
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.keyboardEventKeycode) == kVK_Escape,
           ringCapture.withLock({ $0 }) != .none {
            sendRing(.escape)
            return true
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == kVK_ANSI_M,
              ModifierSet(event.flags) == [.control, .option, .command]
        else { return false }
        // Holding the keys auto-repeats; only the first press toggles.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }

        // Flip immediately here, so it takes effect even if the main thread
        // is busy; the UI catches up asynchronously.
        let enabled = config.withLock { config -> Bool in
            config.enabled.toggle()
            return config.enabled
        }
        if !enabled {
            // The escape hatch must also undo anything in progress, such as
            // a frozen pointer from a gesture or an open ring.
            detector?.reset()
            pressedVirtual.removeAll()
        }
        logger.notice("Kill switch: remapping \(enabled ? "enabled" : "disabled", privacy: .public)")
        let callback = onKillSwitch
        DispatchQueue.main.async { callback?(enabled) }
        return true
    }
}

/// C-compatible trampoline: Quartz calls this, we forward to the engine
/// instance that was passed in as `userInfo`.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<EventTapEngine>.fromOpaque(userInfo).takeUnretainedValue()
    return engine.handle(type: type, event: event)
}
