//
//  TriggerDetectorTests.swift
//  MouseForgeTests
//
//  Drives TriggerDetector with a fake clock to check click / double /
//  triple / hold timing, replay of unbound clicks, drags, and the
//  left/right safety lock.
//

import CoreGraphics
import XCTest
@testable import MouseForge

/// Timers that only fire when the test advances time.
final class FakeScheduler: TriggerScheduler {
    final class Timer: TriggerTimer {
        let fireAt: TimeInterval
        let block: () -> Void
        var cancelled = false
        init(fireAt: TimeInterval, block: @escaping () -> Void) {
            self.fireAt = fireAt
            self.block = block
        }
        func cancel() { cancelled = true }
    }

    private(set) var now: TimeInterval = 0
    private var timers: [Timer] = []

    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> TriggerTimer {
        let timer = Timer(fireAt: now + delay, block: block)
        timers.append(timer)
        return timer
    }

    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let next = timers.filter({ !$0.cancelled && $0.fireAt <= target }).min(by: { $0.fireAt < $1.fireAt }) {
            now = next.fireAt
            next.cancelled = true
            next.block()
        }
        now = target
    }
}

final class TriggerDetectorTests: XCTestCase {
    private enum Event: Equatable {
        case perform(ActionID)
        case replay(button: Int, count: Int)
        case replayDown(button: Int)
        case beginHeld(button: Int)
        case endHeld(button: Int, cancelled: Bool)
        case freeze(Bool)
    }

    private var scheduler: FakeScheduler!
    private var events: [Event] = []
    private var config: RemapConfig!
    private var detector: TriggerDetector!

    private let origin = CGPoint(x: 100, y: 100)

    override func setUp() {
        scheduler = FakeScheduler()
        events = []
        configure([:])
    }

    private func configure(_ bindings: [TriggerKey: ActionConfig], allowPrimary: Bool = false,
                           gestureRepeats: Bool = false, freeze: Bool = true) {
        var general = GeneralSettings()
        general.gestureThreshold = 40
        general.gestureRepeats = gestureRepeats
        general.gestureFreezesPointer = freeze
        general.doubleClickInterval = 0.3
        general.holdThreshold = 0.5
        general.allowPrimaryButtonRemap = allowPrimary
        config = RemapConfig(general: general, bindings: bindings)
        detector = TriggerDetector(
            scheduler: scheduler,
            config: { [unowned self] in self.config },
            output: .init(
                perform: { [unowned self] in self.events.append(.perform($0.actionID)) },
                replayClicks: { [unowned self] in self.events.append(.replay(button: $0, count: $1)) },
                replayDown: { [unowned self] in self.events.append(.replayDown(button: $0)) },
                beginHeld: { [unowned self] button, _ in self.events.append(.beginHeld(button: button)) },
                endHeld: { [unowned self] in self.events.append(.endHeld(button: $0, cancelled: $1)) },
                freezePointer: { [unowned self] in self.events.append(.freeze($0)) }
            )
        )
    }

    private func click(_ button: Int, modifiers: ModifierSet = [], hold: TimeInterval = 0.05) {
        XCTAssertEqual(detector.buttonDown(button, modifiers: modifiers, at: origin), .swallow)
        scheduler.advance(by: hold)
        XCTAssertEqual(detector.buttonUp(button), .swallow)
    }

    private func key(_ button: Int, _ kind: TriggerKind, _ modifiers: ModifierSet = []) -> TriggerKey {
        TriggerKey(button: button, kind: kind, modifiers: modifiers)
    }

    // MARK: - Pass-through

    func testUnboundButtonPassesThrough() {
        XCTAssertEqual(detector.buttonDown(4, modifiers: [], at: origin), .pass)
        XCTAssertEqual(detector.buttonUp(4), .pass)
        XCTAssertEqual(events, [])
    }

    func testDefaultBehaviorBindingPassesThrough() {
        configure([key(4, .click): ActionConfig(.defaultBehavior)])
        XCTAssertEqual(detector.buttonDown(4, modifiers: [], at: origin), .pass)
        XCTAssertEqual(detector.buttonUp(4), .pass)
    }

    func testDisabledPassesThrough() {
        configure([key(4, .click): ActionConfig(.back)])
        config.enabled = false
        XCTAssertEqual(detector.buttonDown(4, modifiers: [], at: origin), .pass)
        XCTAssertEqual(detector.buttonUp(4), .pass)
        XCTAssertEqual(events, [])
    }

    // MARK: - Single click

    func testClickOnlyButtonFiresOnPress() {
        configure([key(4, .click): ActionConfig(.back)])
        XCTAssertEqual(detector.buttonDown(4, modifiers: [], at: origin), .swallow)
        // Fires on the press itself, before the release.
        XCTAssertEqual(events, [.perform(.back)])
        XCTAssertEqual(detector.buttonUp(4), .swallow)
        XCTAssertEqual(events, [.perform(.back)])
    }

    func testClickWithHoldFiresOnReleaseWithoutWaiting() {
        configure([key(4, .click): ActionConfig(.back), key(4, .hold): ActionConfig(.missionControl)])
        _ = detector.buttonDown(4, modifiers: [], at: origin)
        XCTAssertEqual(events, [])
        scheduler.advance(by: 0.1)
        _ = detector.buttonUp(4)
        XCTAssertEqual(events, [.perform(.back)])
    }

    func testMiddleClickOnlyStillFiresOnRelease() {
        configure([key(3, .click): ActionConfig(.missionControl)])
        _ = detector.buttonDown(3, modifiers: [], at: origin)
        XCTAssertEqual(events, [])
        _ = detector.buttonUp(3)
        XCTAssertEqual(events, [.perform(.missionControl)])
    }

    func testSingleClickWaitsWhenDoubleClickIsBound() {
        configure([key(4, .click): ActionConfig(.back), key(4, .doubleClick): ActionConfig(.missionControl)])
        click(4)
        XCTAssertEqual(events, [])
        scheduler.advance(by: 0.29)
        XCTAssertEqual(events, [])
        scheduler.advance(by: 0.02)
        XCTAssertEqual(events, [.perform(.back)])
    }

    // MARK: - Multi click

    func testDoubleClick() {
        configure([key(4, .click): ActionConfig(.back), key(4, .doubleClick): ActionConfig(.missionControl)])
        click(4)
        scheduler.advance(by: 0.1)
        click(4)
        // Nothing higher than double is bound, so it fires right away.
        XCTAssertEqual(events, [.perform(.missionControl)])
        scheduler.advance(by: 1)
        XCTAssertEqual(events, [.perform(.missionControl)])
    }

    func testSlowSecondClickIsTwoSingleClicks() {
        configure([key(4, .click): ActionConfig(.back), key(4, .doubleClick): ActionConfig(.missionControl)])
        click(4)
        scheduler.advance(by: 0.5)
        click(4)
        scheduler.advance(by: 0.5)
        XCTAssertEqual(events, [.perform(.back), .perform(.back)])
    }

    func testTripleClick() {
        configure([
            key(3, .click): ActionConfig(.copy),
            key(3, .doubleClick): ActionConfig(.paste),
            key(3, .tripleClick): ActionConfig(.selectAll),
        ])
        click(3)
        scheduler.advance(by: 0.1)
        click(3)
        XCTAssertEqual(events, []) // Could still become a triple.
        scheduler.advance(by: 0.1)
        click(3)
        XCTAssertEqual(events, [.perform(.selectAll)])
    }

    func testDoubleClickOnlyReplaysNativeSingleClick() {
        configure([key(3, .doubleClick): ActionConfig(.missionControl)])
        click(3)
        scheduler.advance(by: 0.35)
        XCTAssertEqual(events, [.replay(button: 3, count: 1)])
    }

    func testUnboundDoubleWithTripleBoundCountsAsSingles() {
        configure([key(4, .click): ActionConfig(.back), key(4, .tripleClick): ActionConfig(.selectAll)])
        click(4)
        scheduler.advance(by: 0.1)
        click(4)
        scheduler.advance(by: 0.35)
        XCTAssertEqual(events, [.perform(.back), .perform(.back)])
    }

    // MARK: - Hold

    func testHoldFiresAtThresholdWhileStillPressed() {
        configure([key(5, .click): ActionConfig(.forward), key(5, .hold): ActionConfig(.missionControl)])
        XCTAssertEqual(detector.buttonDown(5, modifiers: [], at: origin), .swallow)
        scheduler.advance(by: 0.49)
        XCTAssertEqual(events, [])
        scheduler.advance(by: 0.02)
        XCTAssertEqual(events, [.perform(.missionControl)])
        // Releasing after a hold does nothing more.
        XCTAssertEqual(detector.buttonUp(5), .swallow)
        scheduler.advance(by: 1)
        XCTAssertEqual(events, [.perform(.missionControl)])
    }

    func testShortPressIsClickNotHold() {
        configure([key(5, .click): ActionConfig(.forward), key(5, .hold): ActionConfig(.missionControl)])
        click(5, hold: 0.2)
        scheduler.advance(by: 1)
        XCTAssertEqual(events, [.perform(.forward)])
    }

    func testHoldOnlyButtonReplaysShortClick() {
        configure([key(3, .hold): ActionConfig(.missionControl)])
        click(3, hold: 0.1)
        XCTAssertEqual(events, [.replay(button: 3, count: 1)])
    }

    // MARK: - Modifiers

    func testModifierBindingTakesPriority() {
        configure([key(4, .click): ActionConfig(.back), key(4, .click, .shift): ActionConfig(.closeTab)])
        click(4, modifiers: .shift)
        click(4)
        XCTAssertEqual(events, [.perform(.closeTab), .perform(.back)])
    }

    func testUnboundModifierFallsBackToPlainBinding() {
        configure([key(4, .click): ActionConfig(.back)])
        click(4, modifiers: .command)
        XCTAssertEqual(events, [.perform(.back)])
    }

    func testModifierOnlyBindingLeavesPlainClickAlone() {
        configure([key(4, .click, [.control, .option]): ActionConfig(.missionControl)])
        XCTAssertEqual(detector.buttonDown(4, modifiers: [], at: origin), .pass)
        XCTAssertEqual(detector.buttonUp(4), .pass)
        click(4, modifiers: [.control, .option])
        XCTAssertEqual(events, [.perform(.missionControl)])
    }

    // MARK: - Drag

    func testDragGivesPressBackToApp() {
        configure([key(3, .click): ActionConfig(.missionControl)])
        XCTAssertEqual(detector.buttonDown(3, modifiers: [], at: origin), .swallow)
        // Small jitter is still a click.
        XCTAssertEqual(detector.dragged(3, to: CGPoint(x: 102, y: 101)), .convertToMove)
        XCTAssertEqual(events, [])
        // Real movement becomes a native drag.
        XCTAssertEqual(detector.dragged(3, to: CGPoint(x: 130, y: 100)), .convertToMove)
        XCTAssertEqual(events, [.replayDown(button: 3)])
        XCTAssertEqual(detector.dragged(3, to: CGPoint(x: 140, y: 100)), .pass)
        XCTAssertEqual(detector.buttonUp(3), .pass)
        scheduler.advance(by: 1)
        XCTAssertEqual(events, [.replayDown(button: 3)])
    }

    // MARK: - Safety & kill switch

    func testPrimaryButtonsLockedByDefault() {
        configure([key(1, .click): ActionConfig(.back), key(2, .click): ActionConfig(.forward)])
        XCTAssertEqual(detector.buttonDown(1, modifiers: [], at: origin), .pass)
        XCTAssertEqual(detector.buttonUp(1), .pass)
        XCTAssertEqual(detector.buttonDown(2, modifiers: [], at: origin), .pass)
        XCTAssertEqual(detector.buttonUp(2), .pass)
        XCTAssertEqual(events, [])
    }

    func testPrimaryButtonsRemapWhenUnlocked() {
        configure([key(2, .click): ActionConfig(.copy)], allowPrimary: true)
        click(2)
        XCTAssertEqual(events, [.perform(.copy)])
    }

    func testKillSwitchDuringDoubleClickWindowDropsPendingAction() {
        configure([key(4, .click): ActionConfig(.back), key(4, .doubleClick): ActionConfig(.missionControl)])
        click(4)
        config.enabled = false
        scheduler.advance(by: 1)
        XCTAssertEqual(events, [])
    }

    func testReleaseOfSwallowedPressStaysSwallowedAfterKillSwitch() {
        configure([key(3, .click): ActionConfig(.back)])
        XCTAssertEqual(detector.buttonDown(3, modifiers: [], at: origin), .swallow)
        config.enabled = false
        // The app never saw the press, so it must not see a lone release.
        XCTAssertEqual(detector.buttonUp(3), .swallow)
        XCTAssertEqual(events, [])
    }

    // MARK: - Held actions (Actions Ring)

    func testHoldRingOpensAtThresholdAndSelectsOnRelease() {
        configure([key(4, .click): ActionConfig(.back), key(4, .hold): ActionConfig(.actionsRing)])
        XCTAssertEqual(detector.buttonDown(4, modifiers: [], at: origin), .swallow)
        scheduler.advance(by: 0.6)
        XCTAssertEqual(events, [.beginHeld(button: 4)])
        // Moving to choose a slot keeps the pointer moving.
        XCTAssertEqual(detector.dragged(4, to: CGPoint(x: 200, y: 100)), .convertToMove)
        XCTAssertEqual(detector.buttonUp(4), .swallow)
        XCTAssertEqual(events, [.beginHeld(button: 4), .endHeld(button: 4, cancelled: false)])
    }

    func testQuickClickWithRingOnHoldStillClicks() {
        configure([key(4, .click): ActionConfig(.back), key(4, .hold): ActionConfig(.actionsRing)])
        click(4, hold: 0.1)
        XCTAssertEqual(events, [.perform(.back)])
    }

    func testResetCancelsOpenRing() {
        configure([key(4, .hold): ActionConfig(.actionsRing)])
        _ = detector.buttonDown(4, modifiers: [], at: origin)
        scheduler.advance(by: 0.6)
        detector.reset()
        XCTAssertEqual(events, [.beginHeld(button: 4), .endHeld(button: 4, cancelled: true)])
    }

    func testRingOnClickPerformsImmediately() {
        configure([key(3, .click): ActionConfig(.actionsRing)])
        click(3)
        XCTAssertEqual(events, [.perform(.actionsRing)])
    }

    // MARK: - Gestures

    private var windowsGestures: [TriggerKey: ActionConfig] {
        [
            key(3, .click): ActionConfig(.middleClick),
            key(3, .gestureUp): ActionConfig(.missionControl),
            key(3, .gestureDown): ActionConfig(.appExpose),
            key(3, .gestureLeft): ActionConfig(.spaceLeft),
            key(3, .gestureRight): ActionConfig(.spaceRight),
        ]
    }

    private func move(_ button: Int, _ dx: CGFloat, _ dy: CGFloat, steps: Int = 5) -> [TriggerDetector.DragDecision] {
        (0..<steps).map { _ in detector.dragged(button, to: origin, delta: CGVector(dx: dx / CGFloat(steps), dy: dy / CGFloat(steps))) }
    }

    func testGestureFiresOnceAndSuppressesClick() {
        configure(windowsGestures)
        XCTAssertEqual(detector.buttonDown(3, modifiers: [], at: origin), .swallow)
        XCTAssertEqual(events, [.freeze(true)])
        let decisions = move(3, 0, -60) // up (screen y grows downward)
        XCTAssertTrue(decisions.allSatisfy { $0 == .swallow })
        _ = move(3, 0, -60) // more movement doesn't fire again
        XCTAssertEqual(detector.buttonUp(3), .swallow)
        XCTAssertEqual(events, [.freeze(true), .perform(.missionControl), .freeze(false)])
    }

    func testEachDirection() {
        let expected: [(CGFloat, CGFloat, ActionID)] = [(0, 50, .appExpose), (-50, 0, .spaceLeft), (50, 0, .spaceRight)]
        for (dx, dy, action) in expected {
            events = []
            configure(windowsGestures, freeze: false)
            _ = detector.buttonDown(3, modifiers: [], at: origin)
            _ = move(3, dx, dy)
            _ = detector.buttonUp(3)
            XCTAssertEqual(events, [.perform(action)])
        }
    }

    func testSmallMovementIsStillAClick() {
        configure(windowsGestures, freeze: false)
        _ = detector.buttonDown(3, modifiers: [], at: origin)
        let decisions = move(3, 10, 10)
        XCTAssertEqual(decisions, Array(repeating: .convertToMove, count: 5))
        _ = detector.buttonUp(3)
        XCTAssertEqual(events, [.perform(.middleClick)])
    }

    func testGestureButtonDoesNotFallBackToNativeDrag() {
        configure(windowsGestures, freeze: false)
        _ = detector.buttonDown(3, modifiers: [], at: origin)
        XCTAssertEqual(detector.dragged(3, to: CGPoint(x: 300, y: 100), delta: CGVector(dx: 5, dy: 0)), .convertToMove)
        XCTAssertFalse(events.contains(.replayDown(button: 3)))
    }

    func testRepeatingGestures() {
        configure(windowsGestures, gestureRepeats: true, freeze: false)
        _ = detector.buttonDown(3, modifiers: [], at: origin)
        _ = move(3, 130, 0, steps: 13) // 3+ thresholds of 40
        _ = detector.buttonUp(3)
        XCTAssertEqual(events, Array(repeating: .perform(.spaceRight), count: 3))
    }

    func testGestureCancelsPendingHold() {
        var bindings = windowsGestures
        bindings[key(3, .hold)] = ActionConfig(.launchpad)
        configure(bindings, freeze: false)
        _ = detector.buttonDown(3, modifiers: [], at: origin)
        _ = move(3, 0, 50)
        scheduler.advance(by: 1)
        _ = detector.buttonUp(3)
        XCTAssertEqual(events, [.perform(.appExpose)])
    }

    func testHoldThenRingUnfreezesPointer() {
        var bindings = windowsGestures
        bindings[key(3, .hold)] = ActionConfig(.actionsRing)
        configure(bindings)
        _ = detector.buttonDown(3, modifiers: [], at: origin)
        scheduler.advance(by: 0.6)
        XCTAssertEqual(events, [.freeze(true), .freeze(false), .beginHeld(button: 3)])
        XCTAssertEqual(detector.dragged(3, to: origin, delta: CGVector(dx: 0, dy: -80)), .convertToMove)
        _ = detector.buttonUp(3)
        XCTAssertEqual(events.last, .endHeld(button: 3, cancelled: false))
    }

    func testUnboundDirectionDoesNothing() {
        configure([key(4, .gestureUp): ActionConfig(.missionControl), key(4, .click): ActionConfig(.back)], freeze: false)
        _ = detector.buttonDown(4, modifiers: [], at: origin)
        _ = move(4, 0, 60) // down: unbound
        _ = detector.buttonUp(4)
        XCTAssertEqual(events, [])
    }

    // MARK: - Regressions from review

    func testLostReleaseThenNewPressUnfreezesPointer() {
        configure(windowsGestures)
        _ = detector.buttonDown(3, modifiers: [], at: origin)
        // The release never arrives (e.g. the mouse disconnected); a new press must unfreeze.
        _ = detector.buttonDown(3, modifiers: [], at: origin)
        XCTAssertEqual(events, [.freeze(true), .freeze(false), .freeze(true)])
    }

    func testLostReleaseOfHeldRingCancelsIt() {
        configure([key(4, .hold): ActionConfig(.actionsRing)])
        _ = detector.buttonDown(4, modifiers: [], at: origin)
        scheduler.advance(by: 0.6)
        _ = detector.buttonDown(4, modifiers: [], at: origin)
        XCTAssertEqual(events.prefix(2), [.beginHeld(button: 4), .endHeld(button: 4, cancelled: true)])
    }

    func testVirtualButtonClickSurvivesSmallMovements() {
        let virtual = LogitechButtons.buttonNumber(for: 0x00C4)
        configure([key(virtual, .click): ActionConfig(.missionControl)])
        _ = detector.buttonDown(virtual, modifiers: [], at: origin)
        _ = detector.dragged(virtual, to: CGPoint(x: 200, y: 200), delta: CGVector(dx: 50, dy: 50))
        _ = detector.buttonUp(virtual)
        XCTAssertEqual(events, [.perform(.missionControl)])
    }
}
