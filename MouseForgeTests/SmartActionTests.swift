//
//  SmartActionTests.swift
//  MouseForgeTests
//

import AppKit
import XCTest
@testable import MouseForge

final class SmartActionTests: XCTestCase {
    private var performed: [ActionID] = []
    private var slept: [Double] = []

    private func makeRunner() -> SmartActionRunner {
        SmartActionRunner(
            perform: { [unowned self] in self.performed.append($0.actionID) },
            sleep: { [unowned self] in self.slept.append($0) }
        )
    }

    override func setUp() {
        performed = []
        slept = []
        SmartActionRegistry.shared.update([])
    }

    func testStepsRunInOrderWithDelays() {
        let smartAction = SmartAction(name: "Test", steps: [
            .action(ActionConfig(.copy)),
            .delay(1.5),
            .action(ActionConfig(.paste)),
        ])
        makeRunner().runSteps(of: smartAction, depth: 0, generation: 0)
        XCTAssertEqual(performed, [.copy, .paste])
        let gap = SmartActionRunner.gapBetweenSteps
        XCTAssertEqual(slept, [gap, 1.5, gap])
    }

    func testDelayIsClamped() {
        makeRunner().runSteps(of: SmartAction(name: "T", steps: [.delay(999), .delay(-1)]), depth: 0, generation: 0)
        XCTAssertEqual(slept, [60, SmartActionRunner.gapBetweenSteps, 0.05])
    }

    func testNestedSmartActions() {
        let inner = SmartAction(name: "Inner", steps: [.action(ActionConfig(.undo))])
        let outer = SmartAction(name: "Outer", steps: [.action(ActionConfig(.copy)), .action(inner.actionConfig), .action(ActionConfig(.paste))])
        SmartActionRegistry.shared.update([inner, outer])
        makeRunner().runSteps(of: outer, depth: 0, generation: 0)
        XCTAssertEqual(performed, [.copy, .undo, .paste])
    }

    func testSelfReferenceStopsAtMaxDepth() {
        var loop = SmartAction(name: "Loop", steps: [.action(ActionConfig(.copy))])
        loop.steps.append(.action(loop.actionConfig))
        SmartActionRegistry.shared.update([loop])
        makeRunner().runSteps(of: loop, depth: 0, generation: 0)
        XCTAssertEqual(performed.count, SmartActionRunner.maxDepth)
    }

    func testCancelStopsBeforeNextStep() {
        let runner = makeRunner()
        let smartAction = SmartAction(name: "T", steps: [.action(ActionConfig(.copy)), .action(ActionConfig(.paste))])
        runner.cancelAll() // generation is now 1; a run started at generation 0 must stop
        runner.runSteps(of: smartAction, depth: 0, generation: 0)
        XCTAssertEqual(performed, [])
    }

    func testMissingNestedSmartActionIsSkipped() {
        let smartAction = SmartAction(name: "T", steps: [.action(ActionConfig(.smartAction, text: UUID().uuidString)), .action(ActionConfig(.copy))])
        makeRunner().runSteps(of: smartAction, depth: 0, generation: 0)
        XCTAssertEqual(performed, [.copy])
    }

    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.smartActions = SmartActionTemplates.all
        let decoded = try SettingsStore.decode(try SettingsStore.encode(settings))
        XCTAssertEqual(decoded.smartActions, settings.smartActions)
    }

    func testTemplatesUseRealActions() {
        for template in SmartActionTemplates.all {
            XCTAssertFalse(template.steps.isEmpty, template.name)
            for step in template.steps where step.kind == .action {
                XCTAssertNotNil(ActionLibrary.action(step.action!.actionID), template.name)
            }
            XCTAssertNotNil(NSImage(systemSymbolName: template.symbol, accessibilityDescription: nil), template.symbol)
        }
        for symbol in SmartAction.symbolChoices {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), symbol)
        }
    }

    func testInstantiateGivesFreshIDs() {
        let template = SmartActionTemplates.all[0]
        let copy = SmartActionTemplates.instantiate(template)
        XCTAssertNotEqual(copy.id, template.id)
        XCTAssertTrue(zip(copy.steps, template.steps).allSatisfy { $0.id != $1.id })
    }

    func testDisplayNameUsesSmartActionName() {
        let smartAction = SmartAction(name: "Morning Routine")
        SmartActionRegistry.shared.update([smartAction])
        XCTAssertEqual(ActionLibrary.displayName(for: smartAction.actionConfig), "Morning Routine")
        SmartActionRegistry.shared.update([])
        XCTAssertEqual(ActionLibrary.displayName(for: smartAction.actionConfig), "Missing Smart Action")
    }

    @MainActor
    func testUsages() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)
        let id = store.addSmartAction(SmartAction(name: "M"))
        let config = ActionConfig(.smartAction, text: id.uuidString)
        store.setBinding(config, for: TriggerKey(button: 4, kind: .doubleClick), in: nil)
        store.setRingSlot(2, to: config, in: nil)
        XCTAssertEqual(store.usages(of: id), [
            "All Applications: Actions Ring slot 3",
            "All Applications: Double Click – Back Button",
        ])
    }
}
