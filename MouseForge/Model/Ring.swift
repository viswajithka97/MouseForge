//
//  Ring.swift
//  MouseForge
//
//  The Actions Ring: 8 slots around the cursor plus a center cancel zone.
//  Slot 0 is at the top; slots go clockwise.
//

import CoreGraphics
import Foundation

struct RingConfig: Equatable, Codable, Sendable {
    static let slotCount = 8

    /// Always exactly `slotCount` entries; nil = empty slot.
    private(set) var slots: [ActionConfig?]

    init(_ slots: [ActionConfig?]) {
        var padded = Array(slots.prefix(Self.slotCount))
        padded += Array(repeating: nil, count: Self.slotCount - padded.count)
        self.slots = padded
    }

    subscript(index: Int) -> ActionConfig? {
        get { slots.indices.contains(index) ? slots[index] : nil }
        set { if slots.indices.contains(index) { slots[index] = newValue } }
    }

    mutating func swapAt(_ a: Int, _ b: Int) {
        guard slots.indices.contains(a), slots.indices.contains(b) else { return }
        slots.swapAt(a, b)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([ActionConfig?].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(slots)
    }

    /// The global ring on a fresh install.
    static let factory = RingConfig([
        ActionConfig(.missionControl),
        ActionConfig(.appExpose),
        ActionConfig(.showDesktop),
        ActionConfig(.screenshotArea),
        ActionConfig(.playPause),
        ActionConfig(.spotlight),
        ActionConfig(.launchpad),
        ActionConfig(.lockScreen),
    ])
}

enum RingSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    var title: String { rawValue.capitalized }

    /// Diameter in points.
    var diameter: CGFloat {
        switch self {
        case .small: return 280
        case .medium: return 340
        case .large: return 420
        }
    }
}

/// Where the ring shown for an app comes from.
enum RingSource: Equatable {
    case global
    case builtIn(appName: String)
    case appProfile
}

enum RingGeometry {
    /// Which slot the pointer points at, given its offset from the ring
    /// center in screen coordinates (x right, y up). nil = inside the
    /// center cancel zone.
    static func slot(forOffset offset: CGVector, deadZone: CGFloat, slotCount: Int = RingConfig.slotCount) -> Int? {
        let distance = (offset.dx * offset.dx + offset.dy * offset.dy).squareRoot()
        guard distance >= deadZone else { return nil }
        // 0 at north, increasing clockwise.
        var angle = atan2(offset.dx, offset.dy)
        if angle < 0 { angle += 2 * .pi }
        let sector = 2 * CGFloat.pi / CGFloat(slotCount)
        return Int((angle + sector / 2) / sector) % slotCount
    }

    /// Center of a slot in view coordinates (y down) for a ring of `radius`.
    static func position(ofSlot index: Int, center: CGPoint, radius: CGFloat, slotCount: Int = RingConfig.slotCount) -> CGPoint {
        let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(slotCount)
        return CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }
}

extension AppSettings {
    /// The ring for an app: its own profile ring, else a built-in ring for
    /// popular apps, else the global ring.
    func ring(for bundleID: String?) -> (ring: RingConfig, source: RingSource) {
        if let app = appProfile(for: bundleID), let ring = app.profile.ring {
            return (ring, .appProfile)
        }
        if let bundleID, let preset = AppPresetCatalog.preset(for: bundleID), let ring = preset.ring {
            return (ring, .builtIn(appName: preset.name))
        }
        return (globalProfile.ring ?? .factory, .global)
    }
}
