//
//  ProfileAndSettingsTests.swift
//  MouseForgeTests
//
//  Profile inheritance, JSON round-trips, tolerant decoding, and a sanity
//  check of the action library.
//

import AppKit
import XCTest
@testable import MouseForge

final class ProfileInheritanceTests: XCTestCase {
    func testTestAreaChoiceOnlyAppliesWhileMouseForgeIsInFront() {
        let own = "com.mouse.forge.MouseForge"
        let cursor = "com.todesktop.230313mzl4w4u92"
        // Test Area set to All Applications, but the user switched to Cursor.
        XCTAssertEqual(ProfileManager.effectiveBundleID(frontmost: cursor, testOverride: .some(nil), ownBundleID: own), cursor)
        // In the Test Area itself, its choice wins.
        XCTAssertNil(ProfileManager.effectiveBundleID(frontmost: own, testOverride: .some(nil), ownBundleID: own))
        XCTAssertEqual(ProfileManager.effectiveBundleID(frontmost: own, testOverride: .some(cursor), ownBundleID: own), cursor)
        // No Test Area: the frontmost app.
        XCTAssertEqual(ProfileManager.effectiveBundleID(frontmost: cursor, testOverride: nil, ownBundleID: own), cursor)
    }

    private let back4 = TriggerKey(button: 4, kind: .click)
    private let fwd5 = TriggerKey(button: 5, kind: .click)
    private let hold3 = TriggerKey(button: 3, kind: .hold)

    func testGlobalOnly() {
        let global = Profile(bindings: [back4: ActionConfig(.back)])
        XCTAssertEqual(Profile.resolved(global: global, app: nil), [back4: ActionConfig(.back)])
    }

    func testAppInheritsUnsetAndOverridesSet() {
        let global = Profile(bindings: [back4: ActionConfig(.back), fwd5: ActionConfig(.forward)])
        let app = Profile(bindings: [back4: ActionConfig(.closeTab), hold3: ActionConfig(.missionControl)])
        let resolved = Profile.resolved(global: global, app: app)
        XCTAssertEqual(resolved[back4], ActionConfig(.closeTab)) // overridden
        XCTAssertEqual(resolved[fwd5], ActionConfig(.forward)) // inherited
        XCTAssertEqual(resolved[hold3], ActionConfig(.missionControl)) // app-only
    }

    func testAppDefaultBehaviorHidesGlobalBinding() {
        let global = Profile(bindings: [back4: ActionConfig(.back)])
        let app = Profile(bindings: [back4: ActionConfig(.defaultBehavior)])
        var settings = AppSettings()
        settings.globalProfile = global
        settings.appProfiles = [AppProfile(bundleID: "com.example.game", name: "Game", profile: app)]

        let inGame = ProfileManager.config(for: settings, frontmostBundleID: "com.example.game")
        XCTAssertNil(inGame.bindings(button: 4, modifiers: []))

        let elsewhere = ProfileManager.config(for: settings, frontmostBundleID: "com.apple.Safari")
        XCTAssertEqual(elsewhere.bindings(button: 4, modifiers: [])?.click, ActionConfig(.back))
    }

    @MainActor
    func testStoreResetSemantics() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)

        // Global: reset goes back to the factory default.
        store.setBinding(ActionConfig(.copy), for: back4, in: nil)
        XCTAssertTrue(store.canReset(back4, in: nil))
        store.resetBinding(for: back4, in: nil)
        XCTAssertEqual(store.binding(for: back4, in: nil).action, ActionConfig(.back))
        XCTAssertFalse(store.canReset(back4, in: nil))

        // App: reset removes the override so the global value shows through.
        store.addAppProfile(bundleID: "com.apple.Safari", name: "Safari", appPath: nil)
        XCTAssertEqual(store.binding(for: back4, in: "com.apple.Safari").source, .global)
        store.setBinding(ActionConfig(.closeTab), for: back4, in: "com.apple.Safari")
        XCTAssertEqual(store.binding(for: back4, in: "com.apple.Safari").source, .appOverride)
        store.resetBinding(for: back4, in: "com.apple.Safari")
        XCTAssertEqual(store.binding(for: back4, in: "com.apple.Safari").action, ActionConfig(.back))
        XCTAssertEqual(store.binding(for: back4, in: "com.apple.Safari").source, .global)
    }
}

final class SettingsSerializationTests: XCTestCase {
    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.general.doubleClickInterval = 0.4
        settings.general.allowPrimaryButtonRemap = true
        settings.general.mouseStyle = .generic
        settings.globalProfile.bindings[TriggerKey(button: 3, kind: .hold, modifiers: [.shift, .command])] =
            ActionConfig(.keyboardShortcut, shortcut: KeyCombo(0x11, [.command, .shift]))
        settings.appProfiles = [AppProfile(
            bundleID: "com.apple.Safari", name: "Safari", appPath: "/Applications/Safari.app",
            profile: Profile(bindings: [TriggerKey(button: 4, kind: .doubleClick): ActionConfig(.openURL, text: "apple.com")])
        )]
        settings.knownExtraButtons = [6, 7]

        let data = try SettingsStore.encode(settings)
        XCTAssertEqual(try SettingsStore.decode(data), settings)
    }

    func testEmptyFileUsesDefaults() throws {
        let decoded = try SettingsStore.decode(Data("{}".utf8))
        XCTAssertEqual(decoded, AppSettings())
    }

    func testMissingAndOutOfRangeValuesAreTolerated() throws {
        let json = """
        {"general": {"holdThreshold": 99, "mouseStyle": "spaceship"},
         "globalProfile": {"bindings": [
            {"trigger": {"button": 4, "kind": "click", "modifiers": 0}, "action": {"actionID": "back"}}
         ]}}
        """
        let decoded = try SettingsStore.decode(Data(json.utf8))
        XCTAssertEqual(decoded.general.holdThreshold, GeneralSettings.holdRange.upperBound)
        XCTAssertEqual(decoded.general.mouseStyle, GeneralSettings().mouseStyle)
        XCTAssertEqual(decoded.general.doubleClickInterval, GeneralSettings().doubleClickInterval)
        XCTAssertEqual(decoded.globalProfile.bindings.count, 1)
        XCTAssertTrue(decoded.appProfiles.isEmpty)
    }

    func testJSONIsHumanReadable() throws {
        let text = String(decoding: try SettingsStore.encode(AppSettings()), as: UTF8.self)
        XCTAssertTrue(text.contains("\"actionID\" : \"back\""))
        XCTAssertTrue(text.contains("\"kind\" : \"click\""))
    }
}

final class ActionLibraryTests: XCTestCase {
    func testIDsAreUnique() {
        let ids = ActionLibrary.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEverySymbolExists() {
        for action in ActionLibrary.all {
            XCTAssertNotNil(NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil),
                            "Missing SF Symbol \(action.symbol) for \(action.name)")
        }
        for section in SettingsSection.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil),
                            "Missing SF Symbol \(section.symbol) for \(section.title)")
        }
    }

    func testEveryCategoryHasActions() {
        for category in ActionCategory.allCases {
            XCTAssertFalse(ActionLibrary.all.filter { $0.category == category }.isEmpty, category.title)
        }
    }

    func testSearch() {
        let results = ActionLibrary.grouped(matching: "mission")
        XCTAssertEqual(results.flatMap { $0.actions.map(\.id) }, [.missionControl])
        // Keywords match too.
        XCTAssertTrue(ActionLibrary.grouped(matching: "dnd").flatMap { $0.actions.map(\.id) }.contains(.doNotDisturb))
    }

    func testDisplayNames() {
        XCTAssertEqual(ActionLibrary.displayName(for: ActionConfig(.back)), "Back")
        XCTAssertEqual(ActionLibrary.displayName(for: ActionConfig(.openApp, text: "/Applications/Safari.app")), "Open Safari")
        XCTAssertEqual(ActionLibrary.displayName(for: ActionConfig(.keyboardShortcut)), "Keyboard Shortcut")
    }
}
