//
//  ActionsRingTests.swift
//  MouseForgeTests
//
//  Slot selection by direction, ring resolution (app → built-in → global),
//  storage, and the hold-to-open / release-to-select flow.
//

import AppKit
import CoreGraphics
import Carbon.HIToolbox
import XCTest
@testable import MouseForge

final class RingGeometryTests: XCTestCase {
    private func slot(_ dx: CGFloat, _ dy: CGFloat) -> Int? {
        RingGeometry.slot(forOffset: CGVector(dx: dx, dy: dy), deadZone: 40)
    }

    func testCardinalAndDiagonalDirections() {
        // Screen coordinates: y up. Slot 0 is north, then clockwise.
        XCTAssertEqual(slot(0, 100), 0)
        XCTAssertEqual(slot(70, 70), 1)
        XCTAssertEqual(slot(100, 0), 2)
        XCTAssertEqual(slot(70, -70), 3)
        XCTAssertEqual(slot(0, -100), 4)
        XCTAssertEqual(slot(-70, -70), 5)
        XCTAssertEqual(slot(-100, 0), 6)
        XCTAssertEqual(slot(-70, 70), 7)
    }

    func testSectorBoundaries() {
        // 20° east of north is still north; 25° is north-east.
        XCTAssertEqual(slot(100 * sin(20 * .pi / 180), 100 * cos(20 * .pi / 180)), 0)
        XCTAssertEqual(slot(100 * sin(25 * .pi / 180), 100 * cos(25 * .pi / 180)), 1)
        // Just west of north wraps to slot 0, not 7.
        XCTAssertEqual(slot(-10, 100), 0)
    }

    func testCenterIsCancel() {
        XCTAssertNil(slot(0, 0))
        XCTAssertNil(slot(20, 20))
        XCTAssertNotNil(slot(0, 41))
    }

    func testFarAwayStillSelectsDirection() {
        XCTAssertEqual(slot(2000, 10), 2)
    }

    func testSlotPositionsMatchSelection() {
        // A pointer placed on a drawn slot (view coords, y down) selects that slot.
        let center = CGPoint(x: 200, y: 200)
        for index in 0..<8 {
            let p = RingGeometry.position(ofSlot: index, center: center, radius: 120)
            XCTAssertEqual(slot(p.x - center.x, center.y - p.y), index)
        }
    }
}

final class RingResolutionTests: XCTestCase {
    func testGlobalRingByDefault() {
        let settings = AppSettings()
        XCTAssertEqual(settings.ring(for: nil).ring, .factory)
        XCTAssertEqual(settings.ring(for: "com.example.unknown").source, .global)
    }

    func testBuiltInRingForPopularApps() {
        let settings = AppSettings()
        let safari = settings.ring(for: "com.apple.Safari")
        XCTAssertEqual(safari.source, .builtIn(appName: "Safari"))
        XCTAssertEqual(safari.ring[0], ActionConfig(.newTab))
        XCTAssertEqual(settings.ring(for: "com.google.Chrome").source, .builtIn(appName: "Google Chrome"))
    }

    func testAppProfileRingWins() {
        var settings = AppSettings()
        let custom = RingConfig([ActionConfig(.copy)])
        settings.appProfiles = [AppProfile(bundleID: "com.apple.Safari", name: "Safari", profile: Profile(ring: custom))]
        XCTAssertEqual(settings.ring(for: "com.apple.Safari").ring, custom)
        XCTAssertEqual(settings.ring(for: "com.apple.Safari").source, .appProfile)
    }

    func testAppProfileWithoutRingFallsBackToBuiltIn() {
        var settings = AppSettings()
        settings.appProfiles = [AppProfile(bundleID: "com.apple.Safari", name: "Safari")]
        XCTAssertEqual(settings.ring(for: "com.apple.Safari").source, .builtIn(appName: "Safari"))
    }

    @MainActor
    func testEditingAppRingCopiesThenChanges() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)
        store.addAppProfile(bundleID: "com.apple.Safari", name: "Safari", appPath: nil)

        store.setRingSlot(7, to: ActionConfig(.mute), in: "com.apple.Safari")
        let ring = store.settings.ring(for: "com.apple.Safari")
        XCTAssertEqual(ring.source, .appProfile)
        XCTAssertEqual(ring.ring[0], ActionConfig(.newTab)) // copied from the built-in ring
        XCTAssertEqual(ring.ring[7], ActionConfig(.mute))

        store.swapRingSlots(0, 7, in: "com.apple.Safari")
        XCTAssertEqual(store.settings.ring(for: "com.apple.Safari").ring[0], ActionConfig(.mute))

        XCTAssertTrue(store.canResetRing(in: "com.apple.Safari"))
        store.resetRing(in: "com.apple.Safari")
        XCTAssertEqual(store.settings.ring(for: "com.apple.Safari").source, .builtIn(appName: "Safari"))
    }

    func testRingAlwaysHasEightSlotsAndRoundTrips() throws {
        let short = RingConfig([ActionConfig(.copy), nil, ActionConfig(.paste)])
        XCTAssertEqual(short.slots.count, 8)
        let data = try JSONEncoder().encode(short)
        XCTAssertEqual(try JSONDecoder().decode(RingConfig.self, from: data), short)
        let tooLong = try JSONDecoder().decode(RingConfig.self, from: Data("[null,null,null,null,null,null,null,null,null,null]".utf8))
        XCTAssertEqual(tooLong.slots.count, 8)
    }

    func testEveryPresetRingIsComplete() {
        for preset in AppPresetCatalog.all {
            guard let ring = preset.ring else { continue }
            XCTAssertEqual(ring.slots.compactMap { $0 }.count, 8, preset.name)
        }
    }
}

final class AppPresetTests: XCTestCase {
    func testPresetSymbolsExist() {
        for symbol in AppPresetCatalog.allSymbols {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), symbol)
        }
    }

    func testEveryPresetShortcutHasAnIcon() {
        for preset in AppPresetCatalog.all {
            for action in preset.suggestions where action.actionID == .keyboardShortcut {
                XCTAssertNotNil(action.symbol, "\(preset.name): \(action.label ?? "")")
            }
        }
    }

    func testCodeEditorsGetARunAndDebugRing() throws {
        let settings = AppSettings()
        let (cursorRing, cursorSource) = settings.ring(for: "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(cursorSource, .builtIn(appName: "Cursor"))
        let start = try XCTUnwrap(cursorRing.slots.compactMap { $0 }.first { $0.label == "Start Debugging" })
        XCTAssertEqual(start.shortcut, KeyCombo(kVK_F5, []))
        XCTAssertEqual(settings.ring(for: "com.microsoft.VSCode").source, .builtIn(appName: "Visual Studio Code"))
        XCTAssertEqual(settings.ring(for: "company.thebrowser.dia").source, .builtIn(appName: "Google Chrome"))
    }

    @MainActor
    func testClearRingEmptiesOnlyThatApp() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)
        store.addAppProfile(bundleID: "com.apple.Safari", name: "Safari", appPath: nil)

        store.clearRing(in: "com.apple.Safari")
        XCTAssertTrue(store.settings.ring(for: "com.apple.Safari").ring.slots.allSatisfy { $0 == nil })
        XCTAssertEqual(store.settings.ring(for: nil).ring, .factory)
        store.resetRing(in: "com.apple.Safari")
        XCTAssertEqual(store.settings.ring(for: "com.apple.Safari").source, .builtIn(appName: "Safari"))
    }

    func testSuggestionsIncludeRingAndExtrasWithoutRepeats() throws {
        let cursor = try XCTUnwrap(AppPresetCatalog.preset(for: "com.todesktop.230313mzl4w4u92"))
        let names = cursor.suggestions.map(ActionLibrary.displayName(for:))
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertTrue(names.contains("Step Over"))
        XCTAssertTrue(names.contains("AI Chat"))
        XCTAssertGreaterThan(names.count, 8)
    }

    @MainActor
    func testMyItemsAreSavedPerAppAndEditsUpdateSlots() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)
        let cursor = "com.todesktop.230313mzl4w4u92"
        store.addAppProfile(bundleID: cursor, name: "Cursor", appPath: nil)

        let run = ActionConfig(.runInTerminal, text: "cd ~/app && flutter run", label: "Flutter Run", symbol: "play.fill")
        store.addCustomItem(run, in: cursor)
        store.setRingSlot(2, to: run, in: cursor)
        XCTAssertEqual(store.customItems(in: cursor), [run])
        XCTAssertTrue(store.customItems(in: nil).isEmpty)

        var renamed = run
        renamed.label = "Run App"
        store.replaceCustomItem(at: 0, with: renamed, in: cursor)
        XCTAssertEqual(store.settings.ring(for: cursor).ring[2], renamed)

        let decoded = try SettingsStore.decode(SettingsStore.encode(store.settings))
        XCTAssertEqual(decoded.appProfile(for: cursor)?.profile.customItems, [renamed])

        store.removeCustomItem(at: 0, in: cursor)
        XCTAssertTrue(store.customItems(in: cursor).isEmpty)
        XCTAssertEqual(store.settings.ring(for: cursor).ring[2], renamed) // the slot keeps it
    }

    func testTerminalScriptEscapesTheCommand() {
        let script = SystemControls.terminalScript(for: #"echo "hi" \ done"#)
        XCTAssertTrue(script.contains(#"do script "echo \"hi\" \\ done""#))
        XCTAssertTrue(script.contains(#"tell application "Terminal""#))
    }

    func testItemEditorIconsExist() {
        for symbol in RingItemEditor.symbols {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), symbol)
        }
        XCTAssertNotNil(ActionLibrary.action(.runInTerminal))
    }
}
