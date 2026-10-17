//
//  ScrollMath.swift
//  MouseForge
//
//  The pure parts of the scroll engine: which modifier mode applies, how
//  far a notch travels, and the smooth-scrolling animation. Kept free of
//  CGEvent so it can be unit-tested.
//

import CoreGraphics
import Foundation

enum ScrollMode: Equatable {
    case normal, precise, quick, horizontal, zoom

    var modifiers: (ScrollSettings) -> ModifierSet {
        switch self {
        case .normal: return { _ in [] }
        case .precise: return { $0.preciseModifiers }
        case .quick: return { $0.quickModifiers }
        case .horizontal: return { $0.horizontalModifiers }
        case .zoom: return { $0.zoomModifiers }
        }
    }
}

enum ScrollMath {
    /// Pixels one wheel notch scrolls at speed 1, before acceleration.
    static let pixelsPerNotch: Double = 44
    /// Pixels per "line" in non-smooth mode (macOS's own convention).
    static let pixelsPerLine: Double = 10

    /// The held modifiers must match a mode's set exactly.
    static func mode(for held: ModifierSet, settings: ScrollSettings) -> ScrollMode {
        guard !held.isEmpty else { return .normal }
        if held == settings.zoomModifiers { return .zoom }
        if held == settings.horizontalModifiers { return .horizontal }
        if held == settings.quickModifiers { return .quick }
        if held == settings.preciseModifiers { return .precise }
        return .normal
    }

    static func modeFactor(_ mode: ScrollMode) -> Double {
        switch mode {
        case .precise: return 0.2
        case .quick: return 4
        default: return 1
        }
    }

    /// Faster spinning (shorter time between notches) scrolls further per
    /// notch. Slow, deliberate notches are never accelerated.
    static func accelerationFactor(interval: TimeInterval, acceleration: Double) -> Double {
        guard acceleration > 0, interval > 0 else { return 1 }
        let notchesPerSecond = 1 / interval
        let extra = max(0, notchesPerSecond - 8) / 10
        return min(1 + acceleration * extra, 1 + 6 * acceleration)
    }

    /// Glide time constant in seconds for an inertia setting (0…1).
    static func timeConstant(inertia: Double) -> Double {
        0.035 + inertia.clamped(to: 0...1) * 0.3
    }
}

/// Smooth-scrolling animation: wheel notches add distance, each frame
/// emits a share of what's left (exponential ease-out).
struct ScrollAnimator: Equatable {
    enum Phase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
    }

    struct Frame: Equatable {
        var dx: Int
        var dy: Int
        var phase: Phase
    }

    private(set) var remaining = CGVector.zero
    private var carry = CGVector.zero
    private(set) var isScrolling = false

    var isIdle: Bool { !isScrolling && remaining == .zero }

    /// Adds distance in pixels. Reversing direction drops the rest of the
    /// previous glide so the page responds immediately.
    mutating func add(dx: Double, dy: Double) {
        if dy != 0, remaining.dy != 0, (dy > 0) != (remaining.dy > 0) { remaining.dy = 0; carry.dy = 0 }
        if dx != 0, remaining.dx != 0, (dx > 0) != (remaining.dx > 0) { remaining.dx = 0; carry.dx = 0 }
        remaining.dx += dx
        remaining.dy += dy
    }

    /// Advances by `dt` seconds. Returns the event to post, or nil when idle.
    mutating func step(dt: Double, timeConstant: Double) -> Frame? {
        let done = abs(remaining.dx) < 0.5 && abs(remaining.dy) < 0.5
        if done {
            // Deliver whatever whole pixel is left over before ending.
            let leftX = Int((remaining.dx + carry.dx).rounded())
            let leftY = Int((remaining.dy + carry.dy).rounded())
            remaining = .zero
            carry = .zero
            if leftX != 0 || leftY != 0 {
                let phase: Phase = isScrolling ? .changed : .began
                isScrolling = true
                return Frame(dx: leftX, dy: leftY, phase: phase)
            }
            guard isScrolling else { return nil }
            isScrolling = false
            return Frame(dx: 0, dy: 0, phase: .ended)
        }
        let share = 1 - exp(-dt / max(timeConstant, 0.001))
        var moveX = remaining.dx * share
        var moveY = remaining.dy * share
        // Always make visible progress so the glide ends.
        if abs(moveY) < 1, remaining.dy != 0 { moveY = remaining.dy > 0 ? min(1, remaining.dy) : max(-1, remaining.dy) }
        if abs(moveX) < 1, remaining.dx != 0 { moveX = remaining.dx > 0 ? min(1, remaining.dx) : max(-1, remaining.dx) }
        remaining.dx -= moveX
        remaining.dy -= moveY

        carry.dx += moveX
        carry.dy += moveY
        let outX = Int(carry.dx.rounded(.towardZero))
        let outY = Int(carry.dy.rounded(.towardZero))
        carry.dx -= Double(outX)
        carry.dy -= Double(outY)

        let phase: Phase = isScrolling ? .changed : .began
        isScrolling = true
        return Frame(dx: outX, dy: outY, phase: phase)
    }
}

/// Turns thumb-wheel (or horizontal wheel) movement into discrete steps.
struct StepAccumulator: Equatable {
    private(set) var value: Double = 0

    /// Adds `amount` notches; returns how many whole steps to fire
    /// (positive or negative).
    mutating func add(_ amount: Double, per step: Double) -> Int {
        if amount != 0, value != 0, (amount > 0) != (value > 0) { value = 0 }
        value += amount
        let steps = Int((value / step).rounded(.towardZero))
        value -= Double(steps) * step
        return steps
    }

    mutating func reset() { value = 0 }
}
