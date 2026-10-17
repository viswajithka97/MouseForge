//
//  HIDPPDevice.swift
//  MouseForge
//
//  One HID++ 2.0 device: discovers which features it has, then offers
//  typed calls for each feature MouseForge uses. Every call throws if the
//  device lacks the feature, so callers can simply hide what fails.
//
//  Function numbers and byte layouts follow the HID++ 2.0 feature
//  descriptions (Solaar and libratbag were used only as protocol
//  references).
//

import Foundation

// MARK: - Feature data

struct BatteryInfo: Equatable, Sendable {
    enum Level: String, Sendable { case full, good, low, critical, unknown }
    enum Charging: String, Sendable { case discharging, charging, full, error }

    var percent: Int?
    var level: Level
    var charging: Charging

    var isLow: Bool {
        if charging == .charging || charging == .full { return false }
        if let percent { return percent <= 15 }
        return level == .low || level == .critical
    }

    var summary: String {
        var text = percent.map { "\($0)%" } ?? level.rawValue.capitalized
        switch charging {
        case .charging: text += ", charging"
        case .full: text += ", charged"
        case .error: text += ", charging error"
        case .discharging: break
        }
        return text
    }

    var symbol: String {
        if charging == .charging { return "battery.100percent.bolt" }
        let value = percent ?? (level == .full ? 100 : level == .good ? 60 : level == .low ? 20 : 5)
        switch value {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

struct DPIInfo: Equatable, Sendable {
    var current: Int
    var defaultDPI: Int
    /// Every value the sensor accepts, ascending.
    var supported: [Int]
    /// Extended DPI (0x2202) uses different functions.
    var extended = false

    /// The supported value closest to `dpi`.
    func nearest(_ dpi: Int) -> Int {
        supported.min { abs($0 - dpi) < abs($1 - dpi) } ?? dpi
    }
}

struct SmartShiftInfo: Equatable, Sendable {
    enum Mode: String, CaseIterable, Sendable {
        /// Ratchet that switches to free-spin when flicked fast.
        case smartShift
        case ratchet
        case freeSpin

        var title: String {
            switch self {
            case .smartShift: return "SmartShift (automatic)"
            case .ratchet: return "Always ratchet"
            case .freeSpin: return "Always free-spin"
            }
        }
    }

    var mode: Mode
    /// 1…50: how fast a flick switches to free-spin (higher = harder).
    var sensitivity: Int
    var enhanced: Bool

    static let sensitivityRange = 1...50

    /// Decodes [wheel mode, auto-disengage, default auto-disengage].
    static func decode(_ bytes: [UInt8], enhanced: Bool) -> SmartShiftInfo {
        let wheelMode = bytes.first ?? 2
        let disengage = bytes.count > 1 ? Int(bytes[1]) : 255
        let mode: Mode = wheelMode == 1 ? .freeSpin : (disengage >= 255 || disengage == 0 ? .ratchet : .smartShift)
        let sensitivity = (disengage == 0 || disengage >= 255) ? 30 : min(disengage, 50)
        return SmartShiftInfo(mode: mode, sensitivity: sensitivity, enhanced: enhanced)
    }

    /// Bytes for the set function.
    func encode() -> [UInt8] {
        switch mode {
        case .freeSpin: return [1, UInt8(sensitivity.clamped(to: Self.sensitivityRange)), 0]
        case .ratchet: return [2, 255, 0]
        case .smartShift: return [2, UInt8(sensitivity.clamped(to: Self.sensitivityRange)), 0]
        }
    }
}

struct HiResWheelInfo: Equatable, Sendable {
    var hiRes: Bool
    var inverted: Bool
    var diverted: Bool

    static func decode(_ flags: UInt8) -> HiResWheelInfo {
        HiResWheelInfo(hiRes: flags & 0x02 != 0, inverted: flags & 0x04 != 0, diverted: flags & 0x01 != 0)
    }

    var flags: UInt8 {
        (diverted ? 0x01 : 0) | (hiRes ? 0x02 : 0) | (inverted ? 0x04 : 0)
    }
}

struct ThumbWheelInfo: Equatable, Sendable {
    var diverted: Bool
    var inverted: Bool
    /// Rotation units per full turn while diverted.
    var divertedResolution: Int
}

struct HostInfo: Equatable, Sendable {
    var count: Int
    /// 0-based.
    var current: Int
}

struct ControlInfo: Identifiable, Equatable, Sendable {
    var cid: UInt16
    var taskID: UInt16
    var flags: UInt16
    var diverted = false

    var id: UInt16 { cid }
    var isDivertable: Bool { flags & 0x20 != 0 }
    var supportsRawXY: Bool { flags & 0x100 != 0 }
    var isVirtual: Bool { flags & 0x80 != 0 }

    /// Names for common control IDs.
    var name: String {
        switch cid {
        case 0x0050: return "Left Button"
        case 0x0051: return "Right Button"
        case 0x0052: return "Middle Button"
        case 0x0053: return "Back Button"
        case 0x0056: return "Forward Button"
        case 0x005B: return "Wheel Tilt Left"
        case 0x005D: return "Wheel Tilt Right"
        case 0x00C3: return "Gesture Button"
        case 0x00C4: return "Mode Shift Button"
        case 0x00D7: return "Virtual Gesture Button"
        case 0x00FD: return "DPI Switch"
        case 0x01A0: return "Haptic Sense Panel"
        default: return String(format: "Control 0x%04X", cid)
        }
    }

    /// The standard five buttons work without diversion; only extra
    /// controls are worth diverting.
    var isStandardButton: Bool { (0x0050...0x0056).contains(cid) }
}

struct HapticsInfo: Equatable, Sendable {
    var enabled: Bool
    /// 0…100.
    var level: Int
    /// Device only accepts Off / Low / Medium / High / Maximum.
    var levelsOnly: Bool
    var waveforms: [UInt8]

    static let levelSteps = [25, 50, 75, 100]
}

// MARK: - Device

final class HIDPPDevice: @unchecked Sendable {
    let channel: HIDPPChannel
    let index: UInt8

    private let lock = NSLock()
    private var featureIndexes: [UInt16: UInt8] = [:]
    private(set) var protocolVersion: (major: UInt8, minor: UInt8) = (0, 0)

    init(channel: HIDPPChannel, index: UInt8) {
        self.channel = channel
        self.index = index
    }

    var featureIDs: [UInt16] {
        lock.withLock { featureIndexes.keys.sorted() }
    }

    func has(_ feature: HIDPP.FeatureID) -> Bool {
        lock.withLock { featureIndexes[feature.rawValue] != nil }
    }

    func featureIndex(_ feature: HIDPP.FeatureID) -> UInt8? {
        lock.withLock { featureIndexes[feature.rawValue] }
    }

    /// Feature index for any ID (also used for notifications).
    func feature(at featureIndex: UInt8) -> UInt16? {
        lock.withLock { featureIndexes.first { $0.value == featureIndex }?.key }
    }

    // MARK: Discovery

    /// Root getProtocolVersion; fails if no HID++ 2.0 device answers at
    /// this index (e.g. an empty receiver slot).
    func ping(timeout: TimeInterval = 1.5) async throws {
        let reply = try await channel.request(device: index, featureIndex: 0, function: 1, params: [0, 0, 0x5A], timeout: timeout)
        protocolVersion = (reply.first ?? 0, reply.count > 1 ? reply[1] : 0)
        guard protocolVersion.major >= 2 else { throw HIDPP.Failure.featureNotSupported(0) }
    }

    /// Lists every feature the device has.
    func discoverFeatures() async throws {
        lock.withLock { featureIndexes = [HIDPP.FeatureID.root.rawValue: 0] }
        let setIndex = try await rootFeatureIndex(.featureSet)
        guard let setIndex else {
            // No feature set: ask for each known feature individually.
            for feature in HIDPP.FeatureID.allCases where feature != .root {
                if let index = try? await rootFeatureIndex(feature) {
                    lock.withLock { featureIndexes[feature.rawValue] = index }
                }
            }
            return
        }
        lock.withLock { featureIndexes[HIDPP.FeatureID.featureSet.rawValue] = setIndex }
        let count = Int(try await channel.request(device: index, featureIndex: setIndex, function: 0).first ?? 0)
        for i in 1...max(count, 1) where count > 0 {
            let reply = try await channel.request(device: index, featureIndex: setIndex, function: 1, params: [UInt8(i)])
            let id = HIDPP.uint16(reply, 0)
            lock.withLock { featureIndexes[id] = UInt8(i) }
        }
    }

    private func rootFeatureIndex(_ feature: HIDPP.FeatureID) async throws -> UInt8? {
        let reply = try await channel.request(device: index, featureIndex: 0, function: 0, params: HIDPP.bigEndian(feature.rawValue))
        let featureIndex = reply.first ?? 0
        return featureIndex == 0 ? nil : featureIndex
    }

    func call(_ feature: HIDPP.FeatureID, _ function: UInt8, _ params: [UInt8] = []) async throws -> [UInt8] {
        guard let featureIndex = featureIndex(feature) else { throw HIDPP.Failure.featureNotSupported(feature.rawValue) }
        return try await channel.request(device: index, featureIndex: featureIndex, function: function, params: params)
    }

    // MARK: Name

    func name() async throws -> String {
        let length = Int(try await call(.deviceName, 0).first ?? 0)
        var bytes: [UInt8] = []
        while bytes.count < length {
            let chunk = try await call(.deviceName, 1, [UInt8(bytes.count)])
            let take = min(length - bytes.count, chunk.count)
            guard take > 0 else { break }
            bytes += chunk.prefix(take)
        }
        return String(decoding: bytes.filter { $0 != 0 }, as: UTF8.self)
    }

    // MARK: Battery

    func battery() async throws -> BatteryInfo {
        if has(.unifiedBattery) { return Self.decodeUnifiedBattery(try await call(.unifiedBattery, 1)) }
        if has(.batteryStatus) { return Self.decodeBatteryStatus(try await call(.batteryStatus, 0)) }
        if has(.batteryVoltage) { return Self.decodeBatteryVoltage(try await call(.batteryVoltage, 0)) }
        throw HIDPP.Failure.featureNotSupported(HIDPP.FeatureID.unifiedBattery.rawValue)
    }

    /// [state of charge %, level flags, charging status, …]
    static func decodeUnifiedBattery(_ bytes: [UInt8]) -> BatteryInfo {
        let percent = bytes.first.flatMap { $0 == 0 ? nil : Int($0) }
        let flags = bytes.count > 1 ? bytes[1] : 0
        let level: BatteryInfo.Level = flags & 0x08 != 0 ? .full : flags & 0x04 != 0 ? .good : flags & 0x02 != 0 ? .low : flags & 0x01 != 0 ? .critical : .unknown
        let status = bytes.count > 2 ? bytes[2] : 0
        let charging: BatteryInfo.Charging
        switch status {
        case 1, 2: charging = .charging
        case 3: charging = .full
        case 4: charging = .error
        default: charging = .discharging
        }
        return BatteryInfo(percent: percent, level: level, charging: charging)
    }

    /// [discharge level %, next level, status]
    static func decodeBatteryStatus(_ bytes: [UInt8]) -> BatteryInfo {
        let percent = bytes.first.flatMap { $0 == 0 ? nil : Int($0) }
        let status = bytes.count > 2 ? bytes[2] : 0
        let charging: BatteryInfo.Charging
        switch status {
        case 1, 2, 4: charging = .charging
        case 3: charging = .full
        case 5, 6: charging = .error
        default: charging = .discharging
        }
        return BatteryInfo(percent: percent, level: percent.map(level(forPercent:)) ?? .unknown, charging: charging)
    }

    /// [voltage mV (2 bytes), flags]. Percentage estimated from a typical
    /// Li-ion discharge curve.
    static func decodeBatteryVoltage(_ bytes: [UInt8]) -> BatteryInfo {
        let millivolts = Int(HIDPP.uint16(bytes, 0))
        let flags = bytes.count > 2 ? bytes[2] : 0
        let curve: [(mv: Int, pct: Int)] = [(4186, 100), (4067, 90), (3989, 80), (3922, 70), (3859, 60), (3811, 50),
                                            (3778, 40), (3751, 30), (3717, 20), (3671, 10), (3646, 5), (3579, 2), (3500, 0)]
        var percent = 0
        for (index, point) in curve.enumerated() where millivolts >= point.mv {
            if index == 0 { percent = 100; break }
            let upper = curve[index - 1]
            percent = point.pct + (millivolts - point.mv) * (upper.pct - point.pct) / max(upper.mv - point.mv, 1)
            break
        }
        let charging: BatteryInfo.Charging = flags & 0x80 != 0 ? ((flags & 0x07) == 1 ? .full : .charging) : .discharging
        return BatteryInfo(percent: percent, level: level(forPercent: percent), charging: charging)
    }

    private static func level(forPercent percent: Int) -> BatteryInfo.Level {
        percent > 80 ? .full : percent > 30 ? .good : percent > 10 ? .low : .critical
    }

    // MARK: DPI

    func dpi() async throws -> DPIInfo {
        if has(.adjustableDPI) {
            var list = try await call(.adjustableDPI, 1, [0])
            var values = Self.decodeDPIList(Array(list.dropFirst(1)))
            // Long lists continue on further pages.
            var page: UInt8 = 1
            while values.complete == false, page < 8 {
                list = try await call(.adjustableDPI, 1, [0, 0, page])
                let more = Self.decodeDPIList(Array(list.dropFirst(1)), continuing: values.raw)
                if more.raw.count <= values.raw.count { break }
                values = more
                page += 1
            }
            let current = try await call(.adjustableDPI, 2, [0])
            let (now, defaultDPI) = Self.decodeCurrentDPI(Array(current.dropFirst(1)))
            return DPIInfo(current: now, defaultDPI: defaultDPI, supported: values.dpis)
        }
        if has(.extendedAdjustableDPI) {
            let list = try await call(.extendedAdjustableDPI, 2, [0, 0, 0])
            let values = Self.decodeDPIList(Array(list.dropFirst(3)))
            let current = try await call(.extendedAdjustableDPI, 5, [0])
            let (now, defaultDPI) = Self.decodeCurrentDPI(Array(current.dropFirst(1)))
            return DPIInfo(current: now, defaultDPI: defaultDPI, supported: values.dpis, extended: true)
        }
        throw HIDPP.Failure.featureNotSupported(HIDPP.FeatureID.adjustableDPI.rawValue)
    }

    func setDPI(_ dpi: Int) async throws {
        let value = HIDPP.bigEndian(UInt16(dpi.clamped(to: 50...25600)))
        if has(.adjustableDPI) {
            _ = try await call(.adjustableDPI, 3, [0] + value)
        } else if has(.extendedAdjustableDPI) {
            // X, Y (same as X), LOD unchanged (0).
            _ = try await call(.extendedAdjustableDPI, 6, [0] + value + value + [0])
        } else {
            throw HIDPP.Failure.featureNotSupported(HIDPP.FeatureID.adjustableDPI.rawValue)
        }
    }

    /// Decodes a DPI list: 16-bit values, 0 ends the list, and a value
    /// with the top three bits set (0xE000) is a step that fills the
    /// range between its neighbours.
    static func decodeDPIList(_ bytes: [UInt8], continuing previous: [UInt16] = []) -> (dpis: [Int], raw: [UInt16], complete: Bool) {
        var raw = previous
        var complete = false
        var offset = 0
        while offset + 1 < bytes.count {
            let value = HIDPP.uint16(bytes, offset)
            offset += 2
            if value == 0 {
                complete = true
                break
            }
            raw.append(value)
        }
        var dpis: [Int] = []
        var i = 0
        while i < raw.count {
            let value = raw[i]
            if value & 0xE000 == 0xE000 {
                let step = Int(value & 0x1FFF)
                if step > 0, let start = dpis.last, i + 1 < raw.count {
                    let end = Int(raw[i + 1])
                    var dpi = start + step
                    while dpi <= end {
                        dpis.append(dpi)
                        dpi += step
                    }
                    i += 2
                    continue
                }
            } else {
                dpis.append(Int(value))
            }
            i += 1
        }
        let unique = Array(Set(dpis)).sorted()
        return (unique, raw, complete)
    }

    /// [current (2), default (2)]; a current value of 0 means "default".
    static func decodeCurrentDPI(_ bytes: [UInt8]) -> (current: Int, defaultDPI: Int) {
        let current = Int(HIDPP.uint16(bytes, 0))
        let defaultDPI = Int(HIDPP.uint16(bytes, 2))
        return (current == 0 ? defaultDPI : current, defaultDPI)
    }

    // MARK: SmartShift

    func smartShift() async throws -> SmartShiftInfo {
        if has(.smartShiftEnhanced) {
            return SmartShiftInfo.decode(try await call(.smartShiftEnhanced, 1), enhanced: true)
        }
        return SmartShiftInfo.decode(try await call(.smartShift, 0), enhanced: false)
    }

    func setSmartShift(_ info: SmartShiftInfo) async throws {
        if has(.smartShiftEnhanced) {
            _ = try await call(.smartShiftEnhanced, 2, info.encode())
        } else {
            _ = try await call(.smartShift, 1, info.encode())
        }
    }

    // MARK: Hi-res wheel

    func hiResWheel() async throws -> HiResWheelInfo {
        HiResWheelInfo.decode(try await call(.hiResWheel, 1).first ?? 0)
    }

    func setHiResWheel(_ info: HiResWheelInfo) async throws {
        _ = try await call(.hiResWheel, 2, [info.flags])
    }

    // MARK: Easy-Switch

    func hostInfo() async throws -> HostInfo {
        let reply = try await call(.changeHost, 0)
        return HostInfo(count: Int(reply.first ?? 0), current: reply.count > 1 ? Int(reply[1]) : 0)
    }

    // MARK: Reprogrammable controls

    func controls() async throws -> [ControlInfo] {
        let count = Int(try await call(.reprogControlsV4, 0).first ?? 0)
        var controls: [ControlInfo] = []
        for i in 0..<count {
            let info = try await call(.reprogControlsV4, 1, [UInt8(i)])
            let flags = UInt16(info.count > 4 ? info[4] : 0) | UInt16(info.count > 8 ? info[8] : 0) << 8
            var control = ControlInfo(cid: HIDPP.uint16(info, 0), taskID: HIDPP.uint16(info, 2), flags: flags)
            if control.isDivertable, let reporting = try? await call(.reprogControlsV4, 2, HIDPP.bigEndian(control.cid)) {
                control.diverted = (reporting.count > 2 ? reporting[2] : 0) & 0x01 != 0
            }
            controls.append(control)
        }
        return controls
    }

    /// Sends a control's presses to MouseForge (diverted) or back to the
    /// device's normal behaviour. Temporary: resets when the device does.
    func setDiverted(_ cid: UInt16, _ diverted: Bool) async throws {
        let flags: UInt8 = 0x02 | (diverted ? 0x01 : 0) // divert-valid + divert
        _ = try await call(.reprogControlsV4, 3, HIDPP.bigEndian(cid) + [flags, 0, 0])
    }

    /// Pressed diverted controls from a REPROG_CONTROLS_V4 event (up to 4).
    static func decodeDivertedButtons(_ params: [UInt8]) -> Set<UInt16> {
        var pressed = Set<UInt16>()
        for offset in stride(from: 0, to: min(params.count, 8), by: 2) {
            let cid = HIDPP.uint16(params, offset)
            if cid != 0 { pressed.insert(cid) }
        }
        return pressed
    }

    // MARK: Thumb wheel

    func thumbWheel() async throws -> ThumbWheelInfo {
        let info = try await call(.thumbWheel, 0)
        let status = try await call(.thumbWheel, 1)
        return ThumbWheelInfo(
            diverted: (status.first ?? 0) & 0x01 != 0,
            inverted: (status.count > 1 ? status[1] : 0) & 0x01 != 0,
            divertedResolution: max(Int(HIDPP.uint16(info, 2)), 1)
        )
    }

    func setThumbWheel(diverted: Bool, inverted: Bool) async throws {
        _ = try await call(.thumbWheel, 2, [diverted ? 1 : 0, inverted ? 1 : 0])
    }

    /// Rotation (signed units) from a thumb-wheel event.
    static func decodeThumbWheelRotation(_ params: [UInt8]) -> Int {
        Int(HIDPP.int16(params, 0))
    }

    // MARK: Haptics (MX Master 4)

    func haptics() async throws -> HapticsInfo {
        let capabilities = try await call(.haptics, 0)
        let config = try await call(.haptics, 1)
        let mask = capabilities.count >= 8
            ? UInt32(capabilities[4]) << 24 | UInt32(capabilities[5]) << 16 | UInt32(capabilities[6]) << 8 | UInt32(capabilities[7])
            : 0
        let waveforms = (0..<32).filter { mask & (1 << $0) != 0 }.map { UInt8($0) }
        return HapticsInfo(
            enabled: (config.first ?? 0) & 0x01 != 0,
            level: config.count > 1 ? Int(config[1]) : 50,
            levelsOnly: (capabilities.count > 2 ? capabilities[2] : 0) & 0x01 != 0,
            waveforms: waveforms
        )
    }

    func setHaptics(enabled: Bool, level: Int) async throws {
        _ = try await call(.haptics, 2, [enabled ? 1 : 0, UInt8(level.clamped(to: 0...100))])
    }

    func playHaptic(_ waveform: UInt8) async throws {
        _ = try await call(.haptics, 4, [waveform])
    }
}
