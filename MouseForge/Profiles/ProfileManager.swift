//
//  ProfileManager.swift
//  MouseForge
//
//  Decides which profile is active (the frontmost app's, if it has one,
//  otherwise "All Applications"), applies inheritance, and hands the
//  result to the event tap as a RemapConfig.
//

import Combine
import Foundation

@MainActor
final class ProfileManager: ObservableObject {
    /// Name shown in the menu bar menu.
    @Published private(set) var activeProfileName = "All Applications"
    @Published private(set) var activeBundleID: String?
    /// The app MouseForge is acting for (frontmost, or the test override),
    /// whether or not it has a profile. Used for built-in rings.
    @Published private(set) var effectiveBundleID: String?
    /// Set by the test area: `.some(nil)` forces All Applications,
    /// `.some(id)` forces that app's profile, `nil` follows the frontmost app.
    @Published var testOverride: String??

    private var cancellables: Set<AnyCancellable> = []

    init(store: SettingsStore, watcher: AppWatcher, engine: EventTapEngine) {
        Publishers.CombineLatest3(store.$settings, watcher.$frontmostBundleID, $testOverride)
            // Next main-loop turn, so this never publishes during a view update.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings, frontmost, testOverride in
                let bundleID = Self.effectiveBundleID(frontmost: frontmost, testOverride: testOverride)
                let config = Self.config(for: settings, frontmostBundleID: bundleID)
                engine.update(config)

                let app = settings.appProfile(for: bundleID)
                self?.effectiveBundleID = bundleID
                self?.activeBundleID = app?.bundleID
                self?.activeProfileName = app?.name ?? "All Applications"
            }
            .store(in: &cancellables)
    }

    /// The Test Area's profile choice only counts while MouseForge itself
    /// is in front; in any other app (even with the Test Area still open
    /// behind it) that app's own profile and ring apply.
    nonisolated static func effectiveBundleID(
        frontmost: String?, testOverride: String??, ownBundleID: String? = Bundle.main.bundleIdentifier
    ) -> String? {
        if let testOverride, frontmost == ownBundleID { return testOverride }
        return frontmost
    }

    nonisolated static func config(for settings: AppSettings, frontmostBundleID: String?) -> RemapConfig {
        let app = settings.appProfile(for: frontmostBundleID)
        let bindings = Profile.resolved(global: settings.globalProfile, app: app?.profile)
        var config = RemapConfig(general: settings.general, bindings: bindings)
        config.scroll = settings.scroll(for: frontmostBundleID)
        config.thumbWheel = settings.thumbWheel(for: frontmostBundleID)
        return config
    }
}
