//
//  HIDPP.swift
//  MouseForge
//
//  HID++ 2.0 message format (Logitech's protocol over HID), written from
//  the published protocol descriptions. A long report is 20 bytes:
//
//    [0x11] [device index] [feature index] [function << 4 | software id] [16 parameter bytes]
//
//  Short reports (0x10) are 7 bytes. Device index 0xFF addresses a device
//  connected directly (Bluetooth / USB cable); 1–6 address devices paired
//  to a Bolt or Unifying receiver. Software id 0 marks notifications sent
//  by the device on its own; requests use 1–15 so replies can be matched.
//

import Foundation

enum HIDPP {
    static let shortReportID: UInt8 = 0x10
    static let longReportID: UInt8 = 0x11
    static let shortLength = 7
    static let longLength = 20
    static let directDeviceIndex: UInt8 = 0xFF

    /// Feature index in an error reply (HID++ 2.0 and 1.0 respectively).
    static let errorFeatureIndex: UInt8 = 0xFF
    static let hidpp10ErrorSubID: UInt8 = 0x8F
    /// Receiver notification: a paired device connected or disconnected.
    static let deviceConnectionSubID: UInt8 = 0x41

    enum FeatureID: UInt16, CaseIterable {
        case root = 0x0000
        case featureSet = 0x0001
        case deviceName = 0x0005
        case batteryStatus = 0x1000
        case batteryVoltage = 0x1001
        case unifiedBattery = 0x1004
        case changeHost = 0x1814
        case haptics = 0x19B0
        case reprogControlsV4 = 0x1B04
        case smartShift = 0x2110
        case smartShiftEnhanced = 0x2111
        case hiResWheel = 0x2121
        case thumbWheel = 0x2150
        case adjustableDPI = 0x2201
        case extendedAdjustableDPI = 0x2202

        var name: String {
            switch self {
            case .root: return "Root"
            case .featureSet: return "Feature Set"
            case .deviceName: return "Device Name"
            case .batteryStatus: return "Battery Status"
            case .batteryVoltage: return "Battery Voltage"
            case .unifiedBattery: return "Unified Battery"
            case .changeHost: return "Easy-Switch"
            case .haptics: return "Haptic Feedback"
            case .reprogControlsV4: return "Reprogrammable Controls v4"
            case .smartShift: return "SmartShift"
            case .smartShiftEnhanced: return "SmartShift (enhanced)"
            case .hiResWheel: return "Hi-Res Wheel"
            case .thumbWheel: return "Thumb Wheel"
            case .adjustableDPI: return "Adjustable DPI"
            case .extendedAdjustableDPI: return "Extended Adjustable DPI"
            }
        }
    }

    /// Human-readable name for any feature ID, known or not.
    static func featureName(_ id: UInt16) -> String {
        FeatureID(rawValue: id)?.name ?? String(format: "Feature 0x%04X", id)
    }

    enum ErrorCode: UInt8 {
        case unknown = 0x01
        case invalidArgument = 0x02
        case outOfRange = 0x03
        case hardware = 0x04
        case logitechInternal = 0x05
        case invalidFeatureIndex = 0x06
        case invalidFunction = 0x07
        case busy = 0x08
        case unsupported = 0x09
    }

    enum Failure: Error, Equatable {
        /// The device answered with an error code.
        case deviceError(UInt8)
        case timeout
        case featureNotSupported(UInt16)
        case sendFailed(Int32)
        case disconnected
        case malformedReply
    }

    struct Message: Equatable {
        var reportID: UInt8 = HIDPP.longReportID
        var deviceIndex: UInt8
        var featureIndex: UInt8
        var function: UInt8
        var softwareID: UInt8
        var params: [UInt8]

        /// The raw report (always padded to the report length).
        var bytes: [UInt8] {
            let length = reportID == HIDPP.shortReportID ? HIDPP.shortLength : HIDPP.longLength
            var data = [reportID, deviceIndex, featureIndex, (function & 0x0F) << 4 | (softwareID & 0x0F)]
            data += params.prefix(length - 4)
            data += Array(repeating: 0, count: length - data.count)
            return data
        }

        init(reportID: UInt8 = HIDPP.longReportID, deviceIndex: UInt8, featureIndex: UInt8, function: UInt8, softwareID: UInt8, params: [UInt8] = []) {
            self.reportID = reportID
            self.deviceIndex = deviceIndex
            self.featureIndex = featureIndex
            self.function = function
            self.softwareID = softwareID
            self.params = params
        }

        init?(bytes: [UInt8]) {
            guard bytes.count >= 4, bytes[0] == HIDPP.shortReportID || bytes[0] == HIDPP.longReportID else { return nil }
            reportID = bytes[0]
            deviceIndex = bytes[1]
            featureIndex = bytes[2]
            function = bytes[3] >> 4
            softwareID = bytes[3] & 0x0F
            params = Array(bytes.dropFirst(4))
        }

        var isError: Bool {
            featureIndex == HIDPP.errorFeatureIndex || featureIndex == HIDPP.hidpp10ErrorSubID
        }

        /// For an error reply: the feature index, function byte, and code
        /// of the request that failed. Layout (both HID++ 1.0 and 2.0):
        /// [report id, device, 0xFF or 0x8F, feature index, function|sw, code].
        var errorInfo: (featureIndex: UInt8, functionByte: UInt8, code: UInt8)? {
            guard isError, params.count >= 2 else { return nil }
            return (function << 4 | softwareID, params[0], params[1])
        }
    }

    // MARK: - Byte helpers

    static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard bytes.count > offset + 1 else { return 0 }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    static func int16(_ bytes: [UInt8], _ offset: Int) -> Int16 {
        Int16(bitPattern: uint16(bytes, offset))
    }

    static func bigEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }
}
