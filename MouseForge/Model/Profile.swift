//
//  Profile.swift
//  MouseForge
//
//  A profile is a set of trigger → action bindings. There is one global
//  "All Applications" profile plus optional per-app profiles. An app
//  profile only stores what it overrides; everything else is inherited
//  from the global profile.
//

import Foundation

struct Profile: Equatable, Sendable {
    var bindings: [TriggerKey: ActionConfig] = [:]
    /// Actions Ring slots. nil in an app profile = use the built-in ring
    /// for that app, or the global ring.
    var ring: RingConfig?
    /// nil in an app profile = use the All Applications settings.
    var scroll: ScrollSettings?
    var thumbWheel: ThumbWheelSettings?
    /// Items the user made for this profile's Actions Ring ("My Items").
    var customItems: [ActionConfig] = []

    /// Inheritance: start from the global bindings and let the app profile
    /// replace any trigger it sets.
    static func resolved(global: Profile, app: Profile?) -> [TriggerKey: ActionConfig] {
        guard let app else { return global.bindings }
        return global.bindings.merging(app.bindings) { _, appValue in appValue }
    }

    /// What a fresh install does: Back/Forward on the side buttons. Many Mac
    /// apps (Safari included) ignore buttons 4/5 otherwise.
    /// Holding Back opens the Actions Ring.
    static let factoryGlobal = Profile(
        bindings: [
            TriggerKey(button: MouseButtons.back, kind: .click): ActionConfig(.back),
            TriggerKey(button: MouseButtons.forward, kind: .click): ActionConfig(.forward),
            TriggerKey(button: MouseButtons.back, kind: .hold): ActionConfig(.actionsRing),
        ],
        ring: .factory
    )
}

// Saved as a sorted list instead of a dictionary so the JSON stays readable
// ({"trigger": {...}, "action": {...}}) and diffs nicely.
extension Profile: Codable {
    private struct Entry: Codable {
        var trigger: TriggerKey
        var action: ActionConfig
    }

    private enum CodingKeys: String, CodingKey {
        case bindings, ring, scroll, thumbWheel, customItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decodeIfPresent([Entry].self, forKey: .bindings) ?? []
        bindings = Dictionary(entries.map { ($0.trigger, $0.action) }, uniquingKeysWith: { _, last in last })
        ring = try container.decodeIfPresent(RingConfig.self, forKey: .ring)
        scroll = try container.decodeIfPresent(ScrollSettings.self, forKey: .scroll)
        thumbWheel = try container.decodeIfPresent(ThumbWheelSettings.self, forKey: .thumbWheel)
        customItems = (try? container.decodeIfPresent([ActionConfig].self, forKey: .customItems)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let entries = bindings
            .map { Entry(trigger: $0.key, action: $0.value) }
            .sorted {
                ($0.trigger.button, $0.trigger.modifiers.rawValue, $0.trigger.kind.sortIndex)
                    < ($1.trigger.button, $1.trigger.modifiers.rawValue, $1.trigger.kind.sortIndex)
            }
        try container.encode(entries, forKey: .bindings)
        try container.encodeIfPresent(ring, forKey: .ring)
        try container.encodeIfPresent(scroll, forKey: .scroll)
        try container.encodeIfPresent(thumbWheel, forKey: .thumbWheel)
        if !customItems.isEmpty { try container.encode(customItems, forKey: .customItems) }
    }
}

private extension TriggerKind {
    var sortIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

struct AppProfile: Identifiable, Equatable, Codable, Sendable {
    var bundleID: String
    var name: String
    /// Where the app was when the profile was added; used for its icon.
    var appPath: String?
    var profile = Profile()

    var id: String { bundleID }
}
