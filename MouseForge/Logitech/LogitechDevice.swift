//
//  LogitechDevice.swift
//  MouseForge
//
//  UI-facing state for one Logitech device. Every feature is read on its
//  own; whatever fails (or doesn't exist) stays nil and is hidden.
//

import Combine
import Foundation
import os

enum LogitechConnection: String, Sendable {
    case bolt = "Logi Bolt"
    case unifying = "Unifying Receiver"
    case bluetooth = "Bluetooth"
    case usb = "USB Cable"
}

@MainActor
final class LogitechDevice: ObservableObject, Identifiable {
    nonisolated let id = UUID()
    let hidpp: HIDPPDevice
    let connection: LogitechConnection

    @Published private(set) var name = "Logitech Device"
    @Published private(set) var features: [UInt16] = []
    @Published private(set) var battery: BatteryInfo?
    @Published private(set) var dpi: DPIInfo?
    @Published private(set) var smartShift: SmartShiftInfo?
    @Published private(set) var hiResWheel: HiResWheelInfo?
    @Published private(set) var thumbWheel: ThumbWheelInfo?
    @Published private(set) var host: HostInfo?
    @Published private(set) var controls: [ControlInfo] = []
    @Published private(set) var haptics: HapticsInfo?
    @Published private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.mouse.forge.MouseForge", category: "Logitech")

    init(hidpp: HIDPPDevice, connection: LogitechConnection) {
        self.hidpp = hidpp
        self.connection = connection
    }

    var protocolVersion: String { "\(hidpp.protocolVersion.major).\(hidpp.protocolVersion.minor)" }

    /// Reads everything. Each feature fails independently.
    func refresh() async {
        features = hidpp.featureIDs
        if let name = try? await hidpp.name(), !name.isEmpty { self.name = name }
        battery = try? await hidpp.battery()
        dpi = try? await hidpp.dpi()
        smartShift = (hidpp.has(.smartShift) || hidpp.has(.smartShiftEnhanced)) ? try? await hidpp.smartShift() : nil
        hiResWheel = hidpp.has(.hiResWheel) ? try? await hidpp.hiResWheel() : nil
        thumbWheel = hidpp.has(.thumbWheel) ? try? await hidpp.thumbWheel() : nil
        host = hidpp.has(.changeHost) ? try? await hidpp.hostInfo() : nil
        controls = hidpp.has(.reprogControlsV4) ? (try? await hidpp.controls()) ?? [] : []
        haptics = hidpp.has(.haptics) ? try? await hidpp.haptics() : nil
    }

    func refreshBattery() async {
        if let battery = try? await hidpp.battery() { self.battery = battery }
    }

    // MARK: - Changes

    private func run(_ what: String, _ change: () async throws -> Void) async {
        do {
            try await change()
            lastError = nil
        } catch {
            lastError = "Couldn't change \(what)."
            logger.error("\(what, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    func setDPI(_ value: Int) async {
        guard let info = dpi else { return }
        let target = info.nearest(value)
        await run("DPI") {
            try await hidpp.setDPI(target)
            dpi?.current = target
        }
    }

    func setSmartShift(_ info: SmartShiftInfo) async {
        await run("SmartShift") {
            try await hidpp.setSmartShift(info)
            smartShift = try await hidpp.smartShift()
        }
    }

    func setHiResWheel(_ info: HiResWheelInfo) async {
        await run("the hi-res wheel") {
            try await hidpp.setHiResWheel(info)
            hiResWheel = try await hidpp.hiResWheel()
        }
    }

    func setThumbWheel(diverted: Bool, inverted: Bool) async {
        await run("the thumb wheel") {
            try await hidpp.setThumbWheel(diverted: diverted, inverted: inverted)
            thumbWheel = try await hidpp.thumbWheel()
        }
    }

    func setDiverted(_ cid: UInt16, _ diverted: Bool) async {
        await run("button diversion") {
            try await hidpp.setDiverted(cid, diverted)
            if let index = controls.firstIndex(where: { $0.cid == cid }) { controls[index].diverted = diverted }
        }
    }

    func setHaptics(enabled: Bool, level: Int) async {
        await run("haptic feedback") {
            try await hidpp.setHaptics(enabled: enabled, level: level)
            haptics = try await hidpp.haptics()
        }
    }

    // MARK: - Notifications

    /// Applies a notification the device sent on its own. Returns true if
    /// it was about this device's state.
    @discardableResult
    func apply(notification message: HIDPP.Message) -> Bool {
        guard let feature = hidpp.feature(at: message.featureIndex), message.function == 0 else { return false }
        switch HIDPP.FeatureID(rawValue: feature) {
        case .unifiedBattery:
            battery = HIDPPDevice.decodeUnifiedBattery(message.params)
        case .batteryStatus:
            battery = HIDPPDevice.decodeBatteryStatus(message.params)
        case .batteryVoltage:
            battery = HIDPPDevice.decodeBatteryVoltage(message.params)
        case .changeHost:
            Task { host = try? await hidpp.hostInfo() }
        default:
            return false
        }
        return true
    }
}
