//
//  SmartActionRunner.swift
//  MouseForge
//
//  Runs Smart Actions step by step on their own serial queue, so a long
//  "Wait" never delays other button actions. Smart Actions can include
//  other Smart Actions, up to a small depth (which also stops a macro from
//  running itself forever).
//

import Foundation
import os

final class SmartActionRunner: @unchecked Sendable {
    static let shared = SmartActionRunner(
        perform: { config in
            guard let action = ActionLibrary.action(config.actionID) else { return }
            action.perform(config)
        },
        sleep: { Thread.sleep(forTimeInterval: $0) }
    )

    static let maxDepth = 4
    /// Pause between steps so keystrokes and app launches settle.
    static let gapBetweenSteps: Double = 0.05

    private let perform: (ActionConfig) -> Void
    private let sleep: (Double) -> Void
    private let queue = DispatchQueue(label: "MouseForge.SmartActions", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.mouse.forge.MouseForge", category: "SmartActions")
    private let generation = OSAllocatedUnfairLock(initialState: 0)

    init(perform: @escaping (ActionConfig) -> Void, sleep: @escaping (Double) -> Void) {
        self.perform = perform
        self.sleep = sleep
    }

    func run(_ smartAction: SmartAction) {
        let started = generation.withLock { $0 }
        queue.async { [self] in
            runSteps(of: smartAction, depth: 0, generation: started)
        }
    }

    /// Stops running macros after their current step (kill switch).
    func cancelAll() {
        generation.withLock { $0 += 1 }
    }

    /// Synchronous; called on the runner's queue (or directly by tests).
    func runSteps(of smartAction: SmartAction, depth: Int, generation started: Int) {
        guard depth < Self.maxDepth else {
            logger.error("Smart Action \(smartAction.name, privacy: .public) nested too deeply; stopped")
            return
        }
        for (index, step) in smartAction.steps.enumerated() {
            guard generation.withLock({ $0 }) == started else { return }
            if index > 0 { sleep(Self.gapBetweenSteps) }
            switch step.kind {
            case .delay:
                sleep((step.delay ?? 0).clamped(to: SmartStep.delayRange))
            case .action:
                guard let action = step.action else { continue }
                if action.actionID == .smartAction {
                    if let nested = SmartActionRegistry.shared.smartAction(for: action) {
                        runSteps(of: nested, depth: depth + 1, generation: started)
                    }
                } else {
                    perform(action)
                }
            }
        }
    }
}
