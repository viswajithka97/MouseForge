//
//  ScrollEngine.swift
//  MouseForge
//
//  Handles mouse-wheel events inside the event tap. Trackpads and Magic
//  Mouse (continuous scrolling) are never changed. For a notched wheel it
//  applies reverse direction, speed, acceleration, and the modifier modes
//  (precise / quick / horizontal / zoom), and either rewrites the event in
//  place or replaces it with a smooth pixel animation that runs on its own
//  queue. Horizontal-only wheel input (a thumb wheel or tilt wheel) goes
//  to the thumb-wheel modes.
//

import CoreGraphics
import Foundation

final class ScrollEngine: @unchecked Sendable {
    /// Runs a library action (zoom keys, thumb-wheel actions).
    var perform: (ActionConfig) -> Void = { ActionExecutor.shared.perform($0) }
    var activity: ActivityLog?
    /// Posts one smooth-scroll frame (replaced in tests).
    var postFrame: (_ dx: Int, _ dy: Int, _ phase: Int64, _ flags: CGEventFlags) -> Void = SyntheticEvents.postPixelScroll

    // Tap thread only.
    private var lastNotchTime: TimeInterval = 0
    private var lastNotchSign: Double = 0
    /// Notches per second, smoothed so one quick pair doesn't spike it.
    private var notchRate: Double = 0
    private var thumbSteps = StepAccumulator()
    private var lastThumbTime: TimeInterval = 0

    // Animation queue only.
    private let queue = DispatchQueue(label: "MouseForge.SmoothScroll", qos: .userInteractive)
    private var animator = ScrollAnimator()
    private var timer: DispatchSourceTimer?
    private var lastFrameTime: TimeInterval = 0
    private var timeConstant: Double = 0.2
    private var flags: CGEventFlags = []

    // MARK: - Wheel (tap thread)

    /// Returns the event to deliver (possibly modified), or nil to swallow.
    func handle(_ event: CGEvent, settings: ScrollSettings, thumbWheel: ThumbWheelSettings, enabled: Bool) -> CGEvent? {
        guard enabled, event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return event }

        var dy = notches(event, axis: 1)
        var dx = notches(event, axis: 2)
        guard dx != 0 || dy != 0 else { return event }
        let held = ModifierSet(event.flags)

        // Horizontal-only input without Shift (Shift+wheel is turned into
        // horizontal input by macOS itself) comes from a thumb or tilt wheel.
        if dy == 0, !held.contains(.shift) {
            return handleThumbWheel(event, notches: dx, settings: thumbWheel)
        }

        let mode = ScrollMath.mode(for: held, settings: settings)
        if settings.reverseMouse {
            dy = -dy
            dx = -dx
        }

        if mode == .zoom {
            zoom(steps: dy != 0 ? dy : dx)
            return nil
        }
        if mode == .horizontal, dx == 0 {
            dx = dy
            dy = 0
        }

        let remainingFlags = event.flags.subtracting(mode.modifiers(settings).cgFlags)
        let now = ProcessInfo.processInfo.systemUptime
        let sign: Double = (dy != 0 ? dy : dx) > 0 ? 1 : -1
        let gap = now - lastNotchTime
        if sign != lastNotchSign || gap > 0.3 {
            notchRate = 0
        } else {
            let instant = 1 / max(gap, 0.004)
            notchRate = notchRate == 0 ? instant : notchRate * 0.6 + instant * 0.4
        }
        let interval = notchRate > 0 ? 1 / notchRate : 1
        lastNotchTime = now
        lastNotchSign = sign
        let acceleration = mode == .precise ? 1 : ScrollMath.accelerationFactor(interval: interval, acceleration: settings.acceleration)
        let factor = settings.speed * acceleration * ScrollMath.modeFactor(mode)

        guard settings.smooth else {
            if factor == 1 && !settings.reverseMouse && mode == .normal { return event }
            rewrite(event, dx: dx * factor, dy: dy * factor, flags: remainingFlags)
            return event
        }

        let pixelsX = dx * ScrollMath.pixelsPerNotch * factor
        let pixelsY = dy * ScrollMath.pixelsPerNotch * factor
        let tau = ScrollMath.timeConstant(inertia: settings.inertia)
        queue.async { [self] in
            animator.add(dx: pixelsX, dy: pixelsY)
            timeConstant = tau
            flags = remainingFlags
            startAnimating()
        }
        return nil
    }

    /// Notches on an axis (1 = vertical, 2 = horizontal). Every physical
    /// notch arrives as its own event, but macOS has already multiplied
    /// the line count for fast spins; using that as well as our own
    /// acceleration made fast scrolling jump much too far, so a whole-line
    /// event always counts as one notch. Fractional events (high-resolution
    /// wheels) keep their size.
    private func notches(_ event: CGEvent, axis: Int) -> Double {
        let integer = event.getIntegerValueField(axis == 1 ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2)
        if integer != 0 { return integer > 0 ? 1 : -1 }
        let fixed = event.getDoubleValueField(axis == 1 ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2)
        return max(-1, min(1, fixed))
    }

    /// Non-smooth mode: scale the event's distances in place.
    private func rewrite(_ event: CGEvent, dx: Double, dy: Double, flags: CGEventFlags) {
        func lines(_ value: Double) -> Int64 {
            guard value != 0 else { return 0 }
            let rounded = Int64(value.rounded())
            return rounded == 0 ? (value > 0 ? 1 : -1) : rounded
        }
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: lines(dy))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lines(dx))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64((dy * ScrollMath.pixelsPerLine).rounded()))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64((dx * ScrollMath.pixelsPerLine).rounded()))
        event.flags = flags
    }

    private func zoom(steps: Double) {
        let action = ActionConfig(steps > 0 ? .zoomIn : .zoomOut)
        perform(action)
        activity?.record(symbol: "plus.magnifyingglass", title: "Scroll + modifier", detail: ActionLibrary.displayName(for: action))
    }

    // MARK: - Thumb wheel

    private func handleThumbWheel(_ event: CGEvent, notches: Double, settings: ThumbWheelSettings) -> CGEvent? {
        var amount = notches
        if settings.invert { amount = -amount }
        if settings.mode == .horizontalScroll {
            guard settings.invert || settings.speed != 1 else { return event }
            rewrite(event, dx: amount * settings.speed, dy: 0, flags: event.flags)
            return event
        }
        rotateThumbWheel(by: amount, settings: settings)
        return nil
    }

    /// Thumb-wheel movement in notches (positive = towards the left
    /// action). Also used for a Logitech thumb wheel diverted over HID++.
    func rotateThumbWheel(by amount: Double, settings: ThumbWheelSettings) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastThumbTime > 0.6 { thumbSteps.reset() }
        lastThumbTime = now
        guard let actions = settings.mode.actions(custom: (settings.customLeft, settings.customRight)) else { return }
        let steps = thumbSteps.add(amount, per: settings.notchesPerAction)
        guard steps != 0, let action = steps > 0 ? actions.left : actions.right else { return }
        for _ in 0..<min(abs(steps), 10) { perform(action) }
        activity?.record(symbol: "dial.medium", title: "Thumb wheel", detail: ActionLibrary.displayName(for: action))
    }

    /// Scrolls horizontally by `pixels` (Logitech thumb wheel in
    /// horizontal-scroll mode while diverted).
    func scrollHorizontally(pixels: Double) {
        queue.async { [self] in
            animator.add(dx: pixels, dy: 0)
            timeConstant = ScrollMath.timeConstant(inertia: 0.2)
            flags = []
            startAnimating()
        }
    }

    // MARK: - Animation (animation queue)

    private func startAnimating() {
        guard timer == nil else { return }
        lastFrameTime = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / 120), leeway: .microseconds(500))
        timer.setEventHandler { [weak self] in self?.frame() }
        self.timer = timer
        timer.resume()
    }

    private func frame() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastFrameTime, 0.05)
        lastFrameTime = now
        if let frame = animator.step(dt: dt, timeConstant: timeConstant) {
            postFrame(frame.dx, frame.dy, frame.phase.rawValue, flags)
        }
        if animator.isIdle {
            timer?.cancel()
            timer = nil
        }
    }
}
