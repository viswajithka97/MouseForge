//
//  BackupTests.swift
//  MouseForgeTests
//

import XCTest
@testable import MouseForge

@MainActor
final class BackupTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func safetyCopies() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("settings.before-") }
    }

    func testExportThenImportRestoresEverything() throws {
        let store = SettingsStore(fileURL: folder.appendingPathComponent("settings.json"))
        store.addAppProfile(bundleID: "com.apple.Safari", name: "Safari", appPath: nil)
        store.setBinding(ActionConfig(.closeTab), for: TriggerKey(button: 4, kind: .click), in: "com.apple.Safari")
        store.addSmartAction(SmartAction(name: "Macro", steps: [.delay(1)]))
        let backup = folder.appendingPathComponent("backup.json")
        try store.export(to: backup)
        let saved = store.settings

        try store.resetAll()
        XCTAssertEqual(store.settings, AppSettings())
        XCTAssertEqual(try safetyCopies().count, 1)

        try store.importSettings(from: backup)
        XCTAssertEqual(store.settings, saved)
        XCTAssertEqual(try safetyCopies().count, 2)
        // The settings file itself was written immediately.
        let onDisk = try SettingsStore.decode(Data(contentsOf: store.fileURL))
        XCTAssertEqual(onDisk, saved)
    }

    func testImportRejectsOtherFiles() throws {
        let store = SettingsStore(fileURL: folder.appendingPathComponent("settings.json"))
        let before = store.settings
        let bogus = folder.appendingPathComponent("not-settings.json")
        try Data("[1, 2, 3]".utf8).write(to: bogus)
        XCTAssertThrowsError(try store.importSettings(from: bogus))
        XCTAssertEqual(store.settings, before)
        XCTAssertEqual(try safetyCopies().count, 0)
    }

    func testUnreadableSettingsFileIsKeptAside() throws {
        let file = folder.appendingPathComponent("settings.json")
        try Data("{ not json".utf8).write(to: file)
        let store = SettingsStore(fileURL: file)
        XCTAssertEqual(store.settings, AppSettings())
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("settings.unreadable-") })
    }
}
