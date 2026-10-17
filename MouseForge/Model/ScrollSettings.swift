//
//  ScrollSettings.swift
//  MouseForge
//
//  Wheel and thumb-wheel settings. The global profile always has a value;
//  an app profile either has its own copy (override) or nil (inherit).
//

import Foundation

struct ScrollSettings: Equatable, Sendable {
    /// Turn wheel notches into smooth, pixel-precise scrolling.
    var smooth = true
    /// 0 = stops almost immediately, 1 = long glide.
    var inertia: Double = 0.5
    /// Reverse the mouse wheel only (trackpads are never touched).
    var reverseMouse = false
    /// Distance multiplier.
    var speed: Double = 1
    /// How much faster quick wheel flicks travel (0 = none).
    var acceleration: Double = 1

    /// Hold these while scrolling (empty = feature off). Matched exactly.
    var preciseModifiers: ModifierSet = [.option]
    var quickModifiers: ModifierSet = [.control, .option]
    var horizontalModifiers: ModifierSet = [.shift]
    var zoomModifiers: ModifierSet = [.command]

    static let speedRange: ClosedRange<Double> = 0.25...4
    static let accelerationRange: ClosedRange<Double> = 0...3

    /// Nothing changes the wheel at all (fast path).
    var isPassThrough: Bool {
        !smooth && !reverseMouse && speed == 1 && acceleration == 0
            && preciseModifiers.isEmpty && quickModifiers.isEmpty && horizontalModifiers.isEmpty && zoomModifiers.isEmpty
    }
}

enum ThumbWheelMode: String, Codable, CaseIterable, Sendable {
    case horizontalScroll, zoom, tabs, volume, brightness, timeline, custom

    var title: String {
        switch self {
        case .horizontalScroll: return "Horizontal Scroll"
        case .zoom: return "Zoom"
        case .tabs: return "Switch Tabs"
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .timeline: return "Timeline Scrubbing"
        case .custom: return "Custom Actions"
        }
    }

    /// Actions for one step left / right (nil for horizontal scrolling).
    func actions(custom: (left: ActionConfig?, right: ActionConfig?)) -> (left: ActionConfig?, right: ActionConfig?)? {
        switch self {
        case .horizontalScroll: return nil
        case .zoom: return (ActionConfig(.zoomOut), ActionConfig(.zoomIn))
        case .tabs: return (ActionConfig(.previousTab), ActionConfig(.nextTab))
        case .volume: return (ActionConfig(.volumeDown), ActionConfig(.volumeUp))
        case .brightness: return (ActionConfig(.brightnessDown), ActionConfig(.brightnessUp))
        case .timeline:
            return (ActionConfig.shortcut("Previous Frame", KeyCombo(0x7B), symbol: "backward.frame"),
                    ActionConfig.shortcut("Next Frame", KeyCombo(0x7C), symbol: "forward.frame"))
        case .custom: return custom
        }
    }
}

struct ThumbWheelSettings: Equatable, Sendable {
    var mode: ThumbWheelMode = .horizontalScroll
    var invert = false
    var speed: Double = 1
    var customLeft: ActionConfig?
    var customRight: ActionConfig?

    /// Wheel movement (in notches) per action for step-based modes.
    var notchesPerAction: Double { 1 / speed.clamped(to: 0.25...4) }
}

extension ScrollSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case smooth, inertia, reverseMouse, speed, acceleration
        case preciseModifiers, quickModifiers, horizontalModifiers, zoomModifiers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScrollSettings()
        smooth = try c.decodeIfPresent(Bool.self, forKey: .smooth) ?? d.smooth
        inertia = (try c.decodeIfPresent(Double.self, forKey: .inertia) ?? d.inertia).clamped(to: 0...1)
        reverseMouse = try c.decodeIfPresent(Bool.self, forKey: .reverseMouse) ?? d.reverseMouse
        speed = (try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed).clamped(to: Self.speedRange)
        acceleration = (try c.decodeIfPresent(Double.self, forKey: .acceleration) ?? d.acceleration).clamped(to: Self.accelerationRange)
        preciseModifiers = try c.decodeIfPresent(ModifierSet.self, forKey: .preciseModifiers) ?? d.preciseModifiers
        quickModifiers = try c.decodeIfPresent(ModifierSet.self, forKey: .quickModifiers) ?? d.quickModifiers
        horizontalModifiers = try c.decodeIfPresent(ModifierSet.self, forKey: .horizontalModifiers) ?? d.horizontalModifiers
        zoomModifiers = try c.decodeIfPresent(ModifierSet.self, forKey: .zoomModifiers) ?? d.zoomModifiers
    }
}

extension ThumbWheelSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, invert, speed, customLeft, customRight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ThumbWheelSettings()
        mode = (try? c.decodeIfPresent(ThumbWheelMode.self, forKey: .mode)) ?? d.mode
        invert = try c.decodeIfPresent(Bool.self, forKey: .invert) ?? d.invert
        speed = (try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed).clamped(to: 0.25...4)
        customLeft = try c.decodeIfPresent(ActionConfig.self, forKey: .customLeft)
        customRight = try c.decodeIfPresent(ActionConfig.self, forKey: .customRight)
    }
}

/// Pointer speed and acceleration, applied to every mouse (not trackpads).
struct PointerSettings: Equatable, Codable, Sendable {
    enum Mode: String, Codable, Sendable {
        /// Leave macOS's own settings alone.
        case system
        case custom
    }

    var mode: Mode = .system
    /// Multiplier on the mouse's native resolution.
    var speed: Double = 1
    var accelerationEnabled = true
    /// macOS acceleration amount (System Settings' slider goes 0–3).
    var acceleration: Double = 1

    static let speedRange: ClosedRange<Double> = 0.25...4
    static let accelerationRange: ClosedRange<Double> = 0...5

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PointerSettings()
        mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? d.mode
        speed = (try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed).clamped(to: Self.speedRange)
        accelerationEnabled = try c.decodeIfPresent(Bool.self, forKey: .accelerationEnabled) ?? d.accelerationEnabled
        acceleration = (try c.decodeIfPresent(Double.self, forKey: .acceleration) ?? d.acceleration).clamped(to: Self.accelerationRange)
    }
}
