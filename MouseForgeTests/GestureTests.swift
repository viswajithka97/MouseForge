//
//  GestureTests.swift
//  MouseForgeTests
//
//  Gesture direction detection, presets, and app presets.
//

import CoreGraphics
import XCTest
@testable import MouseForge

final class GestureRecognizerTests: XCTestCase {
    func testDirections() {
        XCTAssertEqual(GestureRecognizer.direction(of: CGVector(dx: 0, dy: -10)), .up)
        XCTAssertEqual(GestureRecognizer.direction(of: CGVector(dx: 0, dy: 10)), .down)
        XCTAssertEqual(GestureRecognizer.direction(of: CGVector(dx: -10, dy: 0)), .left)
        XCTAssertEqual(GestureRecognizer.direction(of: CGVector(dx: 10, dy: 0)), .right)
    }

    func testDominantAxisWinsForDiagonals() {
        XCTAssertEqual(GestureRecognizer.direction(of: CGVector(dx: 30, dy: -20)), .right)
        XCTAssertEqual(GestureRecognizer.direction(of: CGVector(dx: 10, dy: -25)), .up)
        XCTAssertEqual(GestureRecognizer.direction(of: CGVector(dx: -40, dy: 39)), .left)
    }

    func testThresholdAccumulatesAcrossEvents() {
        var recognizer = GestureRecognizer(threshold: 50)
        XCTAssertNil(recognizer.add(dx: 20, dy: 0))
        XCTAssertNil(recognizer.add(dx: 20, dy: 5))
        XCTAssertEqual(recognizer.add(dx: 15, dy: 0), .right)
        // Starts measuring afresh.
        XCTAssertEqual(recognizer.accumulated, .zero)
        XCTAssertNil(recognizer.add(dx: 0, dy: 30))
    }

    func testJitterBackAndForthDoesNotFire() {
        var recognizer = GestureRecognizer(threshold: 30)
        for _ in 0..<20 {
            XCTAssertNil(recognizer.add(dx: 10, dy: 0))
            XCTAssertNil(recognizer.add(dx: -10, dy: 0))
        }
    }
}

final class GesturePresetTests: XCTestCase {
    func testPresetsCoverAllDirections() {
        for preset in GesturePreset.allCases {
            XCTAssertEqual(Set(preset.actions.keys), Set(GestureDirection.allCases), preset.title)
        }
    }

    func testMatching() {
        XCTAssertEqual(GesturePreset.matching(GesturePreset.media.actions), .media)
        XCTAssertNil(GesturePreset.matching([.up: ActionConfig(.copy)]))
    }

    func testGesturesInheritPerApp() {
        var settings = AppSettings()
        settings.globalProfile.bindings[TriggerKey(button: 3, kind: .gestureUp)] = ActionConfig(.missionControl)
        settings.appProfiles = [AppProfile(bundleID: "com.example", name: "Example", profile: Profile(bindings: [
            TriggerKey(button: 3, kind: .gestureDown): ActionConfig(.volumeDown),
        ]))]
        let config = ProfileManager.config(for: settings, frontmostBundleID: "com.example")
        let bindings = config.bindings(button: 3, modifiers: [])
        XCTAssertEqual(bindings?.gestures[.up], ActionConfig(.missionControl))
        XCTAssertEqual(bindings?.gestures[.down], ActionConfig(.volumeDown))
    }
}

final class AppPresetApplyTests: XCTestCase {
    @MainActor
    func testApplyCreatesProfileWithBindingsAndRing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)
        let preset = try XCTUnwrap(AppPresetCatalog.all.first { $0.name == "Spotify" })
        XCTAssertFalse(store.isPresetApplied(preset))

        let bundleID = store.applyPreset(preset)
        XCTAssertTrue(preset.bundleIDs.contains(bundleID))
        let profile = try XCTUnwrap(store.settings.appProfile(for: bundleID))
        XCTAssertEqual(profile.profile.bindings[TriggerKey(button: 5, kind: .click)], ActionConfig(.nextTrack))
        XCTAssertEqual(profile.profile.ring, preset.ring)
        XCTAssertTrue(store.isPresetApplied(preset))

        // Applying again doesn't duplicate the profile.
        store.applyPreset(preset)
        XCTAssertEqual(store.settings.appProfiles.filter { $0.bundleID == bundleID }.count, 1)
    }

    func testPresetsCoverRequiredApps() {
        let names = Set(AppPresetCatalog.all.map(\.name))
        for required in ["Safari", "Google Chrome", "Firefox", "Finder", "Visual Studio Code", "Xcode", "Adobe Photoshop",
                         "Figma", "Final Cut Pro", "Adobe Premiere Pro", "Zoom", "Microsoft Teams", "Slack",
                         "Microsoft Office", "Spotify"] {
            XCTAssertTrue(names.contains(required), required)
        }
    }
}
