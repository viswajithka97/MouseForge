//
//  InputEventLog.swift
//  MouseForge
//
//  A small value type describing one intercepted mouse event, and a
//  thread-safe buffer the event-tap thread writes into and the UI drains.
//

import CoreGraphics
import Foundation
import os

/// One mouse button or scroll event, captured by the event tap.
struct InputEventRecord: Identifiable, Sendable {
    enum Kind: Sendable {
        /// `button` is 1-based, the way users count: 1 = left, 2 = right,
        /// 3 = middle, 4 = back, 5 = forward, 6+ = extra buttons.
        case buttonDown(button: Int, clickCount: Int)
        case buttonUp(button: Int)
        /// `deltaY` / `deltaX` are in lines (fractional for smooth devices).
        /// `isContinuous` is true for trackpads and Magic Mouse, false for
        /// classic notched wheels.
        case scroll(deltaY: Double, deltaX: Double, isContinuous: Bool, phase: Int64, momentumPhase: Int64)
        /// The system switched our tap off (for example because a callback
        /// was too slow); we turn it back on immediately.
        case tapReEnabled(reason: String)
    }

    let id: UInt64
    let time: Date
    let kind: Kind
    let modifiers: CGEventFlags

    var summary: String {
        switch kind {
        case let .buttonDown(button, clickCount):
            return "Button \(button) down" + (clickCount > 1 ? "  (click #\(clickCount))" : "")
        case let .buttonUp(button):
            return "Button \(button) up"
        case let .scroll(dy, dx, continuous, phase, momentum):
            var text = String(format: "Scroll  y: %+.2f  x: %+.2f", dy, dx)
            text += continuous ? "  [trackpad/smooth]" : "  [wheel]"
            if phase != 0 { text += "  phase: \(phase)" }
            if momentum != 0 { text += "  momentum: \(momentum)" }
            return text
        case let .tapReEnabled(reason):
            return "⚠️ Event tap was disabled by macOS (\(reason)), re-enabled"
        }
    }

    var modifierSummary: String {
        var parts: [String] = []
        if modifiers.contains(.maskControl) { parts.append("⌃") }
        if modifiers.contains(.maskAlternate) { parts.append("⌥") }
        if modifiers.contains(.maskShift) { parts.append("⇧") }
        if modifiers.contains(.maskCommand) { parts.append("⌘") }
        if modifiers.contains(.maskSecondaryFn) { parts.append("fn") }
        return parts.joined()
    }
}

/// Lock-protected buffer between the event-tap thread (producer) and the UI
/// (consumer). The lock is held only for an array append or swap, so the
/// tap callback never waits on anything slow.
final class InputEventLog: @unchecked Sendable {
    private struct State {
        var capturing = false
        var pending: [InputEventRecord] = []
        var nextID: UInt64 = 0
        var totalCount: UInt64 = 0
    }

    /// Upper bound so the buffer can't grow forever if nobody drains it
    /// (for example when the log window is closed).
    private let maxPending = 500
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Only records while the Event Log window is open.
    var isCapturing: Bool {
        get { state.withLock { $0.capturing } }
        set { state.withLock { $0.capturing = newValue; $0.pending.removeAll() } }
    }

    func append(_ kind: InputEventRecord.Kind, modifiers: CGEventFlags) {
        state.withLock { s in
            guard s.capturing else { return }
            let now = Date()
            s.nextID &+= 1
            s.totalCount &+= 1
            s.pending.append(InputEventRecord(id: s.nextID, time: now, kind: kind, modifiers: modifiers))
            if s.pending.count > maxPending {
                s.pending.removeFirst(s.pending.count - maxPending / 2)
            }
        }
    }

    /// Returns everything logged since the last drain, oldest first.
    func drain() -> (records: [InputEventRecord], totalCount: UInt64) {
        state.withLock { s in
            let records = s.pending
            s.pending.removeAll(keepingCapacity: true)
            return (records, s.totalCount)
        }
    }
}
