//
//  AppSettings.swift
//  MouseForge
//
//  Everything the user can configure, as one Codable value. Decoding is
//  forgiving: any missing key falls back to its default, so settings files
//  written by older versions keep loading as new options are added.
//

import Foundation

struct GeneralSettings: Equatable, Sendable {
    /// Master switch for remapping (menu toggle and ⌃⌥⌘M kill switch).
    var remappingEnabled = true
    /// How long to wait for another click before deciding it was a single
    /// (or double) click. Only applies to buttons that have a double/triple
    /// click action.
    var doubleClickInterval: Double = 0.3
    /// How long a button must be held before the Hold action fires.
    var holdThreshold: Double = 0.45
    /// Safety lock: left and right click are only remapped when this is on.
    var allowPrimaryButtonRemap = false
    /// Which illustration the Buttons screen shows.
    var mouseStyle: MouseStyle = .ergonomic
    var ringSize: RingSize = .medium
    /// How far (points) the mouse must move while a gesture button is held.
    var gestureThreshold: Double = 50
    /// Show a small arrow + action name when a gesture fires.
    var gestureHints = true
    /// Keep firing while moving (one action per threshold of movement).
    var gestureRepeats = false
    /// Hold the pointer still while gesturing.
    var gestureFreezesPointer = true

    static let gestureThresholdRange: ClosedRange<Double> = 15...200

    static let doubleClickRange: ClosedRange<Double> = 0.15...0.8
    static let holdRange: ClosedRange<Double> = 0.2...1.5
}

enum MouseStyle: String, Codable, CaseIterable, Sendable {
    case generic
    case ergonomic

    var title: String {
        switch self {
        case .generic: return "Standard Mouse"
        case .ergonomic: return "Ergonomic Mouse"
        }
    }
}

extension GeneralSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case remappingEnabled, doubleClickInterval, holdThreshold, allowPrimaryButtonRemap, mouseStyle, ringSize,
             gestureThreshold, gestureHints, gestureRepeats, gestureFreezesPointer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GeneralSettings()
        remappingEnabled = try c.decodeIfPresent(Bool.self, forKey: .remappingEnabled) ?? defaults.remappingEnabled
        doubleClickInterval = (try c.decodeIfPresent(Double.self, forKey: .doubleClickInterval) ?? defaults.doubleClickInterval)
            .clamped(to: Self.doubleClickRange)
        holdThreshold = (try c.decodeIfPresent(Double.self, forKey: .holdThreshold) ?? defaults.holdThreshold)
            .clamped(to: Self.holdRange)
        allowPrimaryButtonRemap = try c.decodeIfPresent(Bool.self, forKey: .allowPrimaryButtonRemap) ?? defaults.allowPrimaryButtonRemap
        mouseStyle = (try? c.decodeIfPresent(MouseStyle.self, forKey: .mouseStyle)) ?? defaults.mouseStyle
        ringSize = (try? c.decodeIfPresent(RingSize.self, forKey: .ringSize)) ?? defaults.ringSize
        gestureThreshold = (try c.decodeIfPresent(Double.self, forKey: .gestureThreshold) ?? defaults.gestureThreshold)
            .clamped(to: Self.gestureThresholdRange)
        gestureHints = try c.decodeIfPresent(Bool.self, forKey: .gestureHints) ?? defaults.gestureHints
        gestureRepeats = try c.decodeIfPresent(Bool.self, forKey: .gestureRepeats) ?? defaults.gestureRepeats
        gestureFreezesPointer = try c.decodeIfPresent(Bool.self, forKey: .gestureFreezesPointer) ?? defaults.gestureFreezesPointer
    }
}

struct AppSettings: Equatable, Sendable {
    static let currentVersion = 1

    var version = AppSettings.currentVersion
    var general = GeneralSettings()
    var globalProfile = Profile.factoryGlobal
    var appProfiles: [AppProfile] = []
    /// Extra buttons (6 and up) seen on any mouse, so they stay listed on
    /// the Buttons screen after a restart.
    var knownExtraButtons: [MouseButtonNumber] = []
    var smartActions: [SmartAction] = []
    var pointer = PointerSettings()
    var logitech = LogitechSettings()

    func appProfile(for bundleID: String?) -> AppProfile? {
        guard let bundleID else { return nil }
        return appProfiles.first { $0.bundleID == bundleID }
    }

    /// Scroll settings in effect for an app (its own, else global).
    func scroll(for bundleID: String?) -> ScrollSettings {
        appProfile(for: bundleID)?.profile.scroll ?? globalProfile.scroll ?? ScrollSettings()
    }

    func thumbWheel(for bundleID: String?) -> ThumbWheelSettings {
        appProfile(for: bundleID)?.profile.thumbWheel ?? globalProfile.thumbWheel ?? ThumbWheelSettings()
    }

    func appProfileIndex(for bundleID: String) -> Int? {
        appProfiles.firstIndex { $0.bundleID == bundleID }
    }
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, general, globalProfile, appProfiles, knownExtraButtons, smartActions, pointer, logitech
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? defaults.version
        general = try c.decodeIfPresent(GeneralSettings.self, forKey: .general) ?? defaults.general
        globalProfile = try c.decodeIfPresent(Profile.self, forKey: .globalProfile) ?? defaults.globalProfile
        appProfiles = try c.decodeIfPresent([AppProfile].self, forKey: .appProfiles) ?? defaults.appProfiles
        knownExtraButtons = try c.decodeIfPresent([MouseButtonNumber].self, forKey: .knownExtraButtons) ?? []
        smartActions = try c.decodeIfPresent([SmartAction].self, forKey: .smartActions) ?? []
        pointer = try c.decodeIfPresent(PointerSettings.self, forKey: .pointer) ?? PointerSettings()
        logitech = try c.decodeIfPresent(LogitechSettings.self, forKey: .logitech) ?? LogitechSettings()
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct LogitechSettings: Equatable, Sendable {
    /// DPI values the "Cycle DPI" action steps through.
    var dpiPresets: [Int] = [800, 1600, 3200]
    var lowBatteryAlerts = true
    /// Divert extra Logitech controls (gesture button etc.) to MouseForge
    /// when they have an action.
    var divertControls = true
    /// Divert the thumb wheel when its mode needs MouseForge.
    var divertThumbWheel = true
    /// MX Master 4: tick when hovering Actions Ring slots / on gestures.
    var hapticTicks = true
}

extension LogitechSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case dpiPresets, lowBatteryAlerts, divertControls, divertThumbWheel, hapticTicks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LogitechSettings()
        dpiPresets = (try c.decodeIfPresent([Int].self, forKey: .dpiPresets) ?? d.dpiPresets).filter { (50...25600).contains($0) }
        lowBatteryAlerts = try c.decodeIfPresent(Bool.self, forKey: .lowBatteryAlerts) ?? d.lowBatteryAlerts
        divertControls = try c.decodeIfPresent(Bool.self, forKey: .divertControls) ?? d.divertControls
        divertThumbWheel = try c.decodeIfPresent(Bool.self, forKey: .divertThumbWheel) ?? d.divertThumbWheel
        hapticTicks = try c.decodeIfPresent(Bool.self, forKey: .hapticTicks) ?? d.hapticTicks
    }
}
