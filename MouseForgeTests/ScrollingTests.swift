//
//  ScrollingTests.swift
//  MouseForgeTests
//
//  Scroll modes, acceleration, the smooth-scroll animator, the event-level
//  scroll engine (with posting captured, never sent to the system), thumb
//  wheel steps, and pointer property values.
//

import CoreGraphics
import XCTest
@testable import MouseForge

final class ScrollMathTests: XCTestCase {
    func testModeNeedsExactModifiers() {
        let settings = ScrollSettings()
        XCTAssertEqual(ScrollMath.mode(for: [], settings: settings), .normal)
        XCTAssertEqual(ScrollMath.mode(for: [.option], settings: settings), .precise)
        XCTAssertEqual(ScrollMath.mode(for: [.control, .option], settings: settings), .quick)
        XCTAssertEqual(ScrollMath.mode(for: [.shift], settings: settings), .horizontal)
        XCTAssertEqual(ScrollMath.mode(for: [.command], settings: settings), .zoom)
        XCTAssertEqual(ScrollMath.mode(for: [.command, .shift], settings: settings), .normal)
    }

    func testDisabledModeIsIgnored() {
        var settings = ScrollSettings()
        settings.zoomModifiers = []
        XCTAssertEqual(ScrollMath.mode(for: [.command], settings: settings), .normal)
    }

    func testAcceleration() {
        XCTAssertEqual(ScrollMath.accelerationFactor(interval: 0.5, acceleration: 1), 1) // slow notches
        XCTAssertEqual(ScrollMath.accelerationFactor(interval: 0.02, acceleration: 0), 1) // acceleration off
        let fast = ScrollMath.accelerationFactor(interval: 0.02, acceleration: 1)
        let faster = ScrollMath.accelerationFactor(interval: 0.01, acceleration: 1)
        XCTAssertGreaterThan(fast, 1)
        XCTAssertGreaterThan(faster, fast)
        XCTAssertLessThanOrEqual(ScrollMath.accelerationFactor(interval: 0.0001, acceleration: 1), 7)
    }

    func testInertiaTimeConstantGrows() {
        XCTAssertLessThan(ScrollMath.timeConstant(inertia: 0), ScrollMath.timeConstant(inertia: 1))
    }
}

final class ScrollAnimatorTests: XCTestCase {
    private func run(_ animator: inout ScrollAnimator, tau: Double = 0.1, maxFrames: Int = 500) -> [ScrollAnimator.Frame] {
        var frames: [ScrollAnimator.Frame] = []
        for _ in 0..<maxFrames {
            guard let frame = animator.step(dt: 1.0 / 120, timeConstant: tau) else { break }
            frames.append(frame)
        }
        return frames
    }

    func testDeliversWholeDistanceWithPhases() {
        var animator = ScrollAnimator()
        animator.add(dx: 0, dy: 132)
        let frames = run(&animator)
        XCTAssertEqual(frames.first?.phase, .began)
        XCTAssertEqual(frames.last, ScrollAnimator.Frame(dx: 0, dy: 0, phase: .ended))
        XCTAssertTrue(frames.dropFirst().dropLast().allSatisfy { $0.phase == .changed })
        XCTAssertEqual(frames.map(\.dy).reduce(0, +), 132)
        XCTAssertTrue(animator.isIdle)
    }

    func testEasesOut() {
        var animator = ScrollAnimator()
        animator.add(dx: 0, dy: -400)
        let frames = run(&animator)
        XCTAssertGreaterThan(abs(frames[0].dy), abs(frames[10].dy))
        XCTAssertEqual(frames.map(\.dy).reduce(0, +), -400)
    }

    func testReversingDropsOldGlide() {
        var animator = ScrollAnimator()
        animator.add(dx: 0, dy: 300)
        _ = animator.step(dt: 1.0 / 120, timeConstant: 0.2)
        animator.add(dx: 0, dy: -50)
        XCTAssertEqual(animator.remaining.dy, -50)
    }

    func testAddingDuringGlideKeepsGoing() {
        var animator = ScrollAnimator()
        animator.add(dx: 0, dy: 100)
        _ = animator.step(dt: 1.0 / 120, timeConstant: 0.2)
        animator.add(dx: 0, dy: 100)
        let frames = run(&animator, tau: 0.2)
        XCTAssertFalse(frames.contains { $0.phase == .began }) // still the same gesture
    }

    func testIdleProducesNothing() {
        var animator = ScrollAnimator()
        XCTAssertNil(animator.step(dt: 0.01, timeConstant: 0.1))
    }
}

final class StepAccumulatorTests: XCTestCase {
    func testWholeSteps() {
        var acc = StepAccumulator()
        XCTAssertEqual(acc.add(0.5, per: 1), 0)
        XCTAssertEqual(acc.add(0.6, per: 1), 1)
        XCTAssertEqual(acc.add(2, per: 1), 2)
        XCTAssertEqual(acc.add(-1, per: 1), -1) // direction change resets the remainder
    }

    func testSensitivity() {
        var acc = StepAccumulator()
        XCTAssertEqual(acc.add(1, per: 0.25), 4)
    }
}

final class ScrollEngineTests: XCTestCase {
    private var performed: [ActionID] = []
    private var frames: [(dx: Int, dy: Int, phase: Int64)] = []
    private var engine: ScrollEngine!

    override func setUp() {
        performed = []
        frames = []
        engine = ScrollEngine()
        engine.perform = { [unowned self] in self.performed.append($0.actionID) }
        engine.postFrame = { [unowned self] dx, dy, phase, _ in self.frames.append((dx, dy, phase)) }
    }

    private func wheel(_ dy: Int32, _ dx: Int32 = 0, flags: CGEventFlags = [], continuous: Bool = false) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        event.flags = flags
        return event
    }

    private var plain: ScrollSettings {
        var s = ScrollSettings()
        s.smooth = false
        s.acceleration = 0
        return s
    }

    func testTrackpadIsUntouched() {
        var settings = ScrollSettings()
        settings.reverseMouse = true
        let event = wheel(3, continuous: true)
        let result = engine.handle(event, settings: settings, thumbWheel: ThumbWheelSettings(), enabled: true)
        XCTAssertTrue(result === event)
        XCTAssertEqual(result?.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3)
    }

    func testDisabledIsUntouched() {
        var settings = plain
        settings.reverseMouse = true
        let result = engine.handle(wheel(1), settings: settings, thumbWheel: ThumbWheelSettings(), enabled: false)
        XCTAssertEqual(result?.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1)
    }

    func testReverseWithoutSmoothing() {
        var settings = plain
        settings.reverseMouse = true
        let result = engine.handle(wheel(1), settings: settings, thumbWheel: ThumbWheelSettings(), enabled: true)
        XCTAssertEqual(result?.getIntegerValueField(.scrollWheelEventDeltaAxis1), -1)
        XCTAssertEqual(result?.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -1)
    }

    func testSpeedScalesLines() {
        var settings = plain
        settings.speed = 3
        let result = engine.handle(wheel(1), settings: settings, thumbWheel: ThumbWheelSettings(), enabled: true)
        XCTAssertEqual(result?.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3)
    }

    func testMacOSAcceleratedLinesCountAsOneNotch() {
        var settings = plain
        settings.speed = 2
        // A fast spin: macOS reports one notch as 6 lines.
        let result = engine.handle(wheel(6), settings: settings, thumbWheel: ThumbWheelSettings(), enabled: true)
        XCTAssertEqual(result?.getIntegerValueField(.scrollWheelEventDeltaAxis1), 2)
        let down = engine.handle(wheel(-4), settings: settings, thumbWheel: ThumbWheelSettings(), enabled: true)
        XCTAssertEqual(down?.getIntegerValueField(.scrollWheelEventDeltaAxis1), -2)
    }

    func testHorizontalModifierMovesAxisAndStripsKey() {
        var settings = plain
        settings.horizontalModifiers = [.option]
        settings.preciseModifiers = []
        let result = engine.handle(wheel(1, flags: .maskAlternate), settings: settings, thumbWheel: ThumbWheelSettings(), enabled: true)
        XCTAssertEqual(result?.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
        XCTAssertEqual(result?.getIntegerValueField(.scrollWheelEventDeltaAxis2), 1)
        XCTAssertFalse(result?.flags.contains(.maskAlternate) ?? true)
    }

    func testZoomModifierSendsZoomAndSwallows() {
        let result = engine.handle(wheel(1, flags: .maskCommand), settings: plain, thumbWheel: ThumbWheelSettings(), enabled: true)
        XCTAssertNil(result)
        _ = engine.handle(wheel(-1, flags: .maskCommand), settings: plain, thumbWheel: ThumbWheelSettings(), enabled: true)
        XCTAssertEqual(performed, [.zoomIn, .zoomOut])
    }

    func testSmoothScrollingAnimates() {
        var settings = ScrollSettings()
        settings.acceleration = 0
        settings.inertia = 0
        XCTAssertNil(engine.handle(wheel(1), settings: settings, thumbWheel: ThumbWheelSettings(), enabled: true))
        let done = expectation(description: "glide ends")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(frames.first?.phase, 1)
        XCTAssertEqual(frames.last?.phase, 4)
        XCTAssertEqual(frames.map(\.dy).reduce(0, +), Int(ScrollMath.pixelsPerNotch))
    }

    func testThumbWheelStepModes() {
        var thumb = ThumbWheelSettings()
        thumb.mode = .volume
        XCTAssertNil(engine.handle(wheel(0, 1), settings: plain, thumbWheel: thumb, enabled: true))
        XCTAssertNil(engine.handle(wheel(0, -1), settings: plain, thumbWheel: thumb, enabled: true))
        XCTAssertEqual(performed, [.volumeDown, .volumeUp])
    }

    func testThumbWheelInvertAndHorizontalScroll() {
        var thumb = ThumbWheelSettings()
        thumb.invert = true
        let result = engine.handle(wheel(0, 1), settings: plain, thumbWheel: thumb, enabled: true)
        XCTAssertEqual(result?.getIntegerValueField(.scrollWheelEventDeltaAxis2), -1)
    }

    func testShiftScrollIsNotThumbWheel() {
        var thumb = ThumbWheelSettings()
        thumb.mode = .volume
        var settings = plain
        settings.horizontalModifiers = []
        let result = engine.handle(wheel(0, 1, flags: .maskShift), settings: settings, thumbWheel: thumb, enabled: true)
        XCTAssertNotNil(result)
        XCTAssertEqual(performed, [])
    }

    func testCustomThumbWheel() {
        var thumb = ThumbWheelSettings()
        thumb.mode = .custom
        thumb.customLeft = ActionConfig(.undo)
        thumb.customRight = ActionConfig(.redo)
        engine.rotateThumbWheel(by: -1, settings: thumb)
        XCTAssertEqual(performed, [.redo])
    }
}

final class PointerValueTests: XCTestCase {
    func testAccelerationValue() {
        var settings = PointerSettings()
        settings.mode = .custom
        settings.acceleration = 1.5
        XCTAssertEqual(PointerEngine.accelerationValue(for: settings), 98304)
        settings.acceleration = 99
        XCTAssertEqual(PointerEngine.accelerationValue(for: settings), 5 * 65536) // clamped
    }

    func testAccelerationOffIsMinusOne() {
        var settings = PointerSettings()
        settings.accelerationEnabled = false
        XCTAssertEqual(PointerEngine.accelerationValue(for: settings), -65536)
    }

    func testScrollAndPointerSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.pointer.mode = .custom
        settings.pointer.speed = 1.75
        var scroll = ScrollSettings()
        scroll.smooth = false
        scroll.zoomModifiers = [.control, .command]
        settings.globalProfile.scroll = scroll
        var thumb = ThumbWheelSettings()
        thumb.mode = .custom
        thumb.customLeft = ActionConfig(.copy)
        settings.appProfiles = [AppProfile(bundleID: "x", name: "X", profile: Profile(thumbWheel: thumb))]
        let decoded = try SettingsStore.decode(try SettingsStore.encode(settings))
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.thumbWheel(for: "x"), thumb)
        XCTAssertEqual(decoded.thumbWheel(for: "y"), ThumbWheelSettings())
        XCTAssertEqual(decoded.scroll(for: "x"), scroll) // inherits global
    }
}
