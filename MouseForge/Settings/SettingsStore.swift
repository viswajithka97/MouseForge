//
//  SettingsStore.swift
//  MouseForge
//
//  Loads and saves AppSettings as JSON in
//  ~/Library/Application Support/MouseForge/settings.json, and offers the
//  editing operations the UI needs (set / reset a binding, add / remove an
//  app profile). Saves are batched so dragging a slider doesn't write the
//  file on every tick.
//

import AppKit
import Combine
import os

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings

    let fileURL: URL
    private let logger = Logger(subsystem: "com.mouse.forge.MouseForge", category: "Settings")
    private var saveCancellable: AnyCancellable?

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MouseForge", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    init(fileURL: URL = SettingsStore.defaultFileURL) {
        self.fileURL = fileURL
        settings = Self.load(from: fileURL, logger: logger)

        saveCancellable = $settings
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] settings in self?.write(settings) }
    }

    // MARK: - Loading & saving

    nonisolated static func encode(_ settings: AppSettings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    nonisolated static func decode(_ data: Data) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: data)
    }

    private static func load(from url: URL, logger: Logger) -> AppSettings {
        guard let data = try? Data(contentsOf: url) else {
            logger.info("No settings file yet; using defaults")
            return AppSettings()
        }
        do {
            return try decode(data)
        } catch {
            // Keep the unreadable file for the user instead of overwriting it.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent().appendingPathComponent("settings.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            logger.error("Settings unreadable (\(error.localizedDescription, privacy: .public)); moved to \(backup.path, privacy: .public)")
            return AppSettings()
        }
    }

    private func write(_ settings: AppSettings) {
        do {
            let data = try Self.encode(settings)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Couldn't save settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Writes immediately (used at quit so the last change isn't lost).
    func flush() {
        write(settings)
    }

    func revealInFinder() {
        if !FileManager.default.fileExists(atPath: fileURL.path) { flush() }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // MARK: - Backup & restore

    enum ImportError: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let reason): return "This file isn't a MouseForge settings backup (\(reason))."
            }
        }
    }

    /// Writes all settings to `url` (same JSON as the settings file).
    func export(to url: URL) throws {
        try Self.encode(settings).write(to: url, options: .atomic)
    }

    /// Replaces all settings with the backup at `url`. The current
    /// settings are saved next to the settings file first, just in case.
    func importSettings(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported: AppSettings
        do {
            imported = try Self.decode(data)
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        try saveSafetyCopy(named: "before-import")
        settings = imported
        flush()
    }

    /// Back to a fresh install (a safety copy is kept).
    func resetAll() throws {
        try saveSafetyCopy(named: "before-reset")
        settings = AppSettings()
        flush()
    }

    private func saveSafetyCopy(named name: String) throws {
        let folder = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try Self.encode(settings).write(to: folder.appendingPathComponent("settings.\(name)-\(stamp).json"), options: .atomic)
    }

    // MARK: - Bindings

    /// Where a binding's value comes from, for the "overrides" badge.
    enum BindingSource: Equatable {
        case unset
        case global
        /// Set in this app profile, hiding the global value.
        case appOverride
    }

    /// `bundleID == nil` means the global "All Applications" profile.
    func binding(for trigger: TriggerKey, in bundleID: String?) -> (action: ActionConfig?, source: BindingSource) {
        if let bundleID, let app = settings.appProfile(for: bundleID), let action = app.profile.bindings[trigger] {
            return (action, .appOverride)
        }
        if let action = settings.globalProfile.bindings[trigger] {
            return (action, .global)
        }
        return (nil, .unset)
    }

    func setBinding(_ action: ActionConfig, for trigger: TriggerKey, in bundleID: String?) {
        if let bundleID, let index = settings.appProfileIndex(for: bundleID) {
            settings.appProfiles[index].profile.bindings[trigger] = action
        } else {
            settings.globalProfile.bindings[trigger] = action
        }
    }

    /// App profile: remove the override (inherit from global again).
    /// Global profile: back to the factory default (Back / Forward on the
    /// side buttons, nothing elsewhere).
    func resetBinding(for trigger: TriggerKey, in bundleID: String?) {
        if let bundleID, let index = settings.appProfileIndex(for: bundleID) {
            settings.appProfiles[index].profile.bindings[trigger] = nil
        } else {
            settings.globalProfile.bindings[trigger] = Profile.factoryGlobal.bindings[trigger]
        }
    }

    func canReset(_ trigger: TriggerKey, in bundleID: String?) -> Bool {
        if let bundleID {
            return settings.appProfile(for: bundleID)?.profile.bindings[trigger] != nil
        }
        return settings.globalProfile.bindings[trigger] != Profile.factoryGlobal.bindings[trigger]
    }

    /// Bindings set directly in a profile (not inherited).
    func ownBindings(in bundleID: String?) -> [TriggerKey: ActionConfig] {
        if let bundleID { return settings.appProfile(for: bundleID)?.profile.bindings ?? [:] }
        return settings.globalProfile.bindings
    }

    // MARK: - Actions Ring

    /// Changes one slot. Editing an app's ring for the first time copies
    /// the ring it currently uses (built-in or global) into its profile.
    func setRingSlot(_ index: Int, to action: ActionConfig?, in bundleID: String?) {
        updateRing(in: bundleID) { $0[index] = action }
    }

    func swapRingSlots(_ a: Int, _ b: Int, in bundleID: String?) {
        updateRing(in: bundleID) { $0.swapAt(a, b) }
    }

    private func updateRing(in bundleID: String?, _ change: (inout RingConfig) -> Void) {
        var ring = settings.ring(for: bundleID).ring
        change(&ring)
        if let bundleID {
            guard let index = settings.appProfileIndex(for: bundleID) else { return }
            settings.appProfiles[index].profile.ring = ring
        } else {
            settings.globalProfile.ring = ring
        }
    }

    // MARK: - My Items (user-made ring items)

    func customItems(in bundleID: String?) -> [ActionConfig] {
        guard let bundleID else { return settings.globalProfile.customItems }
        return settings.appProfile(for: bundleID)?.profile.customItems ?? []
    }

    func addCustomItem(_ item: ActionConfig, in bundleID: String?) {
        updateCustomItems(in: bundleID) { $0.append(item) }
    }

    /// Replaces an item and every ring slot that holds it.
    func replaceCustomItem(at index: Int, with item: ActionConfig, in bundleID: String?) {
        let items = customItems(in: bundleID)
        let old = items.indices.contains(index) ? items[index] : nil
        updateCustomItems(in: bundleID) { if $0.indices.contains(index) { $0[index] = item } }
        if let old {
            updateRing(in: bundleID) { ring in
                for slot in 0..<RingConfig.slotCount where ring[slot] == old { ring[slot] = item }
            }
        }
    }

    func removeCustomItem(at index: Int, in bundleID: String?) {
        updateCustomItems(in: bundleID) { if $0.indices.contains(index) { $0.remove(at: index) } }
    }

    private func updateCustomItems(in bundleID: String?, _ change: (inout [ActionConfig]) -> Void) {
        if let bundleID {
            guard let index = settings.appProfileIndex(for: bundleID) else { return }
            change(&settings.appProfiles[index].profile.customItems)
        } else {
            change(&settings.globalProfile.customItems)
        }
    }

    /// Empties every slot, to build a ring from scratch.
    func clearRing(in bundleID: String?) {
        updateRing(in: bundleID) { $0 = RingConfig([]) }
    }

    /// App: drop the custom ring. Global: back to the factory ring.
    func resetRing(in bundleID: String?) {
        if let bundleID, let index = settings.appProfileIndex(for: bundleID) {
            settings.appProfiles[index].profile.ring = nil
        } else {
            settings.globalProfile.ring = .factory
        }
    }

    func canResetRing(in bundleID: String?) -> Bool {
        if let bundleID { return settings.appProfile(for: bundleID)?.profile.ring != nil }
        return (settings.globalProfile.ring ?? .factory) != .factory
    }

    // MARK: - Buttons

    /// Buttons that can be configured: the ones the connected mice declare
    /// (middle, back, forward, … up to `hardwareButtons`; 3–5 when unknown),
    /// extra buttons seen so far, and left/right when unlocked.
    func configurableButtons(hardwareButtons: Int?) -> [MouseButtonNumber] {
        var buttons: Set<MouseButtonNumber> = settings.general.allowPrimaryButtonRemap ? [1, 2] : []
        buttons.formUnion(3...max(3, hardwareButtons ?? 5))
        buttons.formUnion(settings.knownExtraButtons.filter { $0 > 2 })
        return buttons.sorted()
    }

    /// Buttons with at least one gesture direction (own or inherited).
    func gestureButtons(in bundleID: String?) -> [MouseButtonNumber] {
        let app = settings.appProfile(for: bundleID)?.profile
        let resolved = Profile.resolved(global: settings.globalProfile, app: app)
        return Set(resolved.filter { $0.key.kind.gestureDirection != nil && !$0.value.isDefaultBehavior && $0.value.actionID != .doNothing }
            .map(\.key.button)).sorted()
    }

    // MARK: - Smart Actions

    @discardableResult
    func addSmartAction(_ smartAction: SmartAction) -> UUID {
        settings.smartActions.append(smartAction)
        return smartAction.id
    }

    func removeSmartAction(_ id: UUID) {
        settings.smartActions.removeAll { $0.id == id }
    }

    @discardableResult
    func duplicateSmartAction(_ id: UUID) -> UUID? {
        guard let original = settings.smartActions.first(where: { $0.id == id }) else { return nil }
        var copy = SmartActionTemplates.instantiate(original)
        copy.name += " Copy"
        return addSmartAction(copy)
    }

    /// Where a Smart Action is used, e.g. "All Applications: Hold – Back Button".
    func usages(of id: UUID) -> [String] {
        let idString = id.uuidString
        func uses(_ action: ActionConfig?) -> Bool {
            action?.actionID == .smartAction && action?.text == idString
        }
        var result: [String] = []
        let profiles = [("All Applications", settings.globalProfile)] + settings.appProfiles.map { ($0.name, $0.profile) }
        for (name, profile) in profiles {
            for (trigger, action) in profile.bindings where uses(action) {
                result.append("\(name): \(trigger.displayName)")
            }
            for (index, slot) in (profile.ring?.slots ?? []).enumerated() where uses(slot) {
                result.append("\(name): Actions Ring slot \(index + 1)")
            }
        }
        for other in settings.smartActions where other.id != id && other.steps.contains(where: { uses($0.action) }) {
            result.append("Smart Action: \(other.name)")
        }
        return result.sorted()
    }

    // MARK: - App presets

    /// Creates (or updates) the app's profile with the preset's buttons and
    /// ring. Returns the bundle ID used.
    @discardableResult
    func applyPreset(_ preset: AppPreset) -> String {
        let installed = preset.bundleIDs.lazy
            .compactMap { id in NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { (id, $0) } }
            .first
        let bundleID = installed?.0 ?? preset.bundleIDs[0]
        let name = installed.map { FileManager.default.displayName(atPath: $0.1.path).replacingOccurrences(of: ".app", with: "") } ?? preset.name
        addAppProfile(bundleID: bundleID, name: name, appPath: installed?.1.path)
        if let index = settings.appProfileIndex(for: bundleID) {
            settings.appProfiles[index].profile.bindings.merge(preset.bindings) { _, new in new }
            if let ring = preset.ring { settings.appProfiles[index].profile.ring = ring }
        }
        return bundleID
    }

    func isPresetApplied(_ preset: AppPreset) -> Bool {
        guard let profile = preset.bundleIDs.lazy.compactMap({ self.settings.appProfile(for: $0) }).first else { return false }
        return preset.bindings.allSatisfy { profile.profile.bindings[$0.key] == $0.value }
    }

    // MARK: - App profiles

    func addAppProfile(bundleID: String, name: String, appPath: String?) {
        guard settings.appProfile(for: bundleID) == nil else { return }
        settings.appProfiles.append(AppProfile(bundleID: bundleID, name: name, appPath: appPath))
    }

    func removeAppProfile(bundleID: String) {
        settings.appProfiles.removeAll { $0.bundleID == bundleID }
    }

    func addKnownExtraButton(_ button: MouseButtonNumber) {
        guard !settings.knownExtraButtons.contains(button) else { return }
        settings.knownExtraButtons.append(button)
        settings.knownExtraButtons.sort()
    }
}
