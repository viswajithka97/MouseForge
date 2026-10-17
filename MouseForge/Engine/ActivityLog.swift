//
//  ActivityLog.swift
//  MouseForge
//
//  What MouseForge itself did: triggers recognized, gestures, ring
//  selections, scroll handling. Shown in the live test area. Recording is
//  off unless the test area is open, so the event tap pays nothing for it
//  normally.
//

import Foundation
import os

struct ActivityRecord: Identifiable, Sendable {
    let id: UInt64
    let time: Date
    let symbol: String
    let title: String
    let detail: String
}

final class ActivityLog: @unchecked Sendable {
    private struct State {
        var capturing = false
        var pending: [ActivityRecord] = []
        var nextID: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var isCapturing: Bool {
        get { state.withLock { $0.capturing } }
        set { state.withLock { $0.capturing = newValue; $0.pending.removeAll() } }
    }

    func record(symbol: String, title: String, detail: String) {
        let now = Date()
        state.withLock { s in
            guard s.capturing else { return }
            s.nextID &+= 1
            s.pending.append(ActivityRecord(id: s.nextID, time: now, symbol: symbol, title: title, detail: detail))
            if s.pending.count > 200 { s.pending.removeFirst(100) }
        }
    }

    func record(trigger: TriggerKey, action: ActionConfig?) {
        guard isCapturing else { return }
        let detail = action.map(ActionLibrary.displayName(for:)) ?? "Original click passed to the app"
        record(symbol: action.map(ActionLibrary.symbol(for:)) ?? "computermouse", title: trigger.displayName, detail: detail)
    }

    func drain() -> [ActivityRecord] {
        state.withLock { s in
            let records = s.pending
            s.pending.removeAll(keepingCapacity: true)
            return records
        }
    }
}
