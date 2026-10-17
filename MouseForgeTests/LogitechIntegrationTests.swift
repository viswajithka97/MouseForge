//
//  LogitechIntegrationTests.swift
//  MouseForgeTests
//
//  Which Logitech controls get diverted, thumb-wheel diversion, rotation
//  conversion, and virtual buttons in the trigger engine.
//

import CoreGraphics
import XCTest
@testable import MouseForge

final class LogitechIntegrationTests: XCTestCase {
    private let gesture = ControlInfo(cid: 0x00C3, taskID: 0xA9, flags: 0x0130)
    private let modeShift = ControlInfo(cid: 0x00C4, taskID: 0xAA, flags: 0x0030)
    private let back = ControlInfo(cid: 0x0053, taskID: 0x38, flags: 0x0031)
    private let fixed = ControlInfo(cid: 0x00FD, taskID: 0x01, flags: 0x0000) // not divertable

    private var gestureButton: Int { LogitechButtons.buttonNumber(for: 0x00C3) }

    func testVirtualButtonNumbers() {
        XCTAssertEqual(gestureButton, 1195)
        XCTAssertEqual(LogitechButtons.controlID(for: 1195), 0x00C3)
        XCTAssertNil(LogitechButtons.controlID(for: 5))
        XCTAssertTrue(LogitechButtons.isVirtual(1195))
        XCTAssertEqual(MouseButtons.name(1195), "Gesture Button")
    }

    func testOnlyBoundExtraControlsAreDiverted() {
        var settings = AppSettings()
        XCTAssertTrue(LogitechIntegration.diversionChanges(for: [gesture, modeShift, back, fixed], settings: settings).isEmpty)

        settings.globalProfile.bindings[TriggerKey(button: gestureButton, kind: .gestureUp)] = ActionConfig(.missionControl)
        let changes = LogitechIntegration.diversionChanges(for: [gesture, modeShift, back, fixed], settings: settings)
        XCTAssertEqual(changes.map(\.cid), [0x00C3])
        XCTAssertEqual(changes.map(\.divert), [true])
    }

    func testBindingInAnAppProfileAlsoCounts() {
        var settings = AppSettings()
        settings.appProfiles = [AppProfile(bundleID: "a", name: "A", profile: Profile(bindings: [
            TriggerKey(button: LogitechButtons.buttonNumber(for: 0x00C4), kind: .click): ActionConfig(.copy),
        ]))]
        XCTAssertEqual(LogitechIntegration.boundControls(in: settings), [0x00C4])
    }

    func testDefaultBehaviorDoesNotDivert() {
        var settings = AppSettings()
        settings.globalProfile.bindings[TriggerKey(button: gestureButton, kind: .click)] = ActionConfig(.defaultBehavior)
        XCTAssertTrue(LogitechIntegration.boundControls(in: settings).isEmpty)
    }

    func testUndivertWhenUnboundOrSwitchedOff() {
        var divertedGesture = gesture
        divertedGesture.diverted = true
        var settings = AppSettings()
        XCTAssertEqual(LogitechIntegration.diversionChanges(for: [divertedGesture], settings: settings).map(\.divert), [false])

        settings.globalProfile.bindings[TriggerKey(button: gestureButton, kind: .click)] = ActionConfig(.copy)
        XCTAssertTrue(LogitechIntegration.diversionChanges(for: [divertedGesture], settings: settings).isEmpty)
        settings.logitech.divertControls = false
        XCTAssertEqual(LogitechIntegration.diversionChanges(for: [divertedGesture], settings: settings).map(\.divert), [false])
    }

    func testThumbWheelNeedsMouseForgeOnlyForNonNativeModes() {
        var settings = AppSettings()
        XCTAssertFalse(LogitechIntegration.needsThumbWheel(in: settings))
        var thumb = ThumbWheelSettings()
        thumb.mode = .volume
        settings.appProfiles = [AppProfile(bundleID: "a", name: "A", profile: Profile(thumbWheel: thumb))]
        XCTAssertTrue(LogitechIntegration.needsThumbWheel(in: settings))
        settings.appProfiles = []
        settings.globalProfile.thumbWheel = ThumbWheelSettings(mode: .horizontalScroll, invert: true)
        XCTAssertTrue(LogitechIntegration.needsThumbWheel(in: settings))
    }

    func testRotationToNotches() {
        XCTAssertEqual(LogitechIntegration.notches(rotation: 6, resolution: 120), -1)
        XCTAssertEqual(LogitechIntegration.notches(rotation: -12, resolution: 120), 2)
        XCTAssertEqual(LogitechIntegration.notches(rotation: 3, resolution: 0), -3) // never divides by zero
    }

    func testVirtualButtonGestureThroughDetector() {
        let scheduler = FakeScheduler()
        var performed: [ActionID] = []
        var general = GeneralSettings()
        general.gestureThreshold = 30
        general.gestureFreezesPointer = false
        let config = RemapConfig(general: general, bindings: [
            TriggerKey(button: gestureButton, kind: .click): ActionConfig(.missionControl),
            TriggerKey(button: gestureButton, kind: .gestureLeft): ActionConfig(.spaceLeft),
        ])
        let detector = TriggerDetector(
            scheduler: scheduler, config: { config },
            output: .init(perform: { performed.append($0.actionID) }, replayClicks: { _, _ in }, replayDown: { _ in })
        )
        _ = detector.buttonDown(gestureButton, modifiers: [], at: .zero)
        _ = detector.dragged(gestureButton, to: .zero, delta: CGVector(dx: -40, dy: 0))
        _ = detector.buttonUp(gestureButton)
        _ = detector.buttonDown(gestureButton, modifiers: [], at: .zero)
        _ = detector.buttonUp(gestureButton)
        XCTAssertEqual(performed, [.spaceLeft, .missionControl])
    }
}
