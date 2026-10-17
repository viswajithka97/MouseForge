//
//  FakeHIDPPDevice.swift
//  MouseForgeTests
//
//  A simulated HID++ 2.0 device behind a transport: answers root and
//  feature-set requests from a feature table and lets tests script any
//  other function's reply. Replies arrive asynchronously, like the real
//  thing.
//

import Foundation
@testable import MouseForge

final class FakeHIDPPDevice: HIDPPTransport, @unchecked Sendable {
    var onReport: (([UInt8]) -> Void)?

    /// Device indexes that answer (0xFF = direct; 1–6 behind a receiver).
    var presentIndexes: Set<UInt8> = [HIDPP.directDeviceIndex]
    /// Feature IDs in feature-index order (index 0 is root).
    var features: [UInt16] = [0x0000, 0x0001]
    /// Replies for (feature ID, function); params of the request are passed in.
    var handlers: [String: ([UInt8]) -> [UInt8]] = [:]
    /// Don't answer at all (timeout tests).
    var silent = false

    private(set) var sent: [HIDPP.Message] = []
    private let lock = NSLock()
    /// Real devices deliver input reports one at a time on one thread.
    private let reportQueue = DispatchQueue(label: "FakeHIDPPDevice.reports")

    static func key(_ feature: HIDPP.FeatureID, _ function: UInt8) -> String { "\(feature.rawValue)-\(function)" }

    func on(_ feature: HIDPP.FeatureID, _ function: UInt8, reply: @escaping ([UInt8]) -> [UInt8]) {
        if !features.contains(feature.rawValue) { features.append(feature.rawValue) }
        handlers[Self.key(feature, function)] = reply
    }

    func send(_ report: [UInt8]) throws {
        guard let message = HIDPP.Message(bytes: report) else { return }
        lock.withLock { sent.append(message) }
        guard !silent else { return }
        reportQueue.asyncAfter(deadline: .now() + 0.002) { [self] in
            onReport?(reply(to: message).bytes)
        }
    }

    func push(_ message: HIDPP.Message) {
        reportQueue.async { [self] in onReport?(message.bytes) }
    }

    private func error(_ message: HIDPP.Message, _ code: UInt8, hidpp10: Bool = false) -> HIDPP.Message {
        // [id, device, 0xFF/0x8F, failed feature index, failed function|sw, code]
        HIDPP.Message(
            deviceIndex: message.deviceIndex,
            featureIndex: hidpp10 ? HIDPP.hidpp10ErrorSubID : HIDPP.errorFeatureIndex,
            function: message.featureIndex >> 4, softwareID: message.featureIndex & 0x0F,
            params: [message.bytes[3], code]
        )
    }

    private func reply(to message: HIDPP.Message) -> HIDPP.Message {
        guard presentIndexes.contains(message.deviceIndex) else {
            return error(message, 0x09, hidpp10: true) // unknown device
        }
        var answer = message
        let index = Int(message.featureIndex)
        guard features.indices.contains(index) else { return error(message, 0x06) }
        let featureID = features[index]

        switch (featureID, message.function) {
        case (0x0000, 0): // root.getFeature
            let wanted = HIDPP.uint16(message.params, 0)
            answer.params = [UInt8(features.firstIndex(of: wanted) ?? 0), 0, 0]
        case (0x0000, 1): // root.getProtocolVersion
            answer.params = [4, 5, message.params.count > 2 ? message.params[2] : 0]
        case (0x0001, 0): // featureSet.getCount (excluding root)
            answer.params = [UInt8(features.count - 1)]
        case (0x0001, 1): // featureSet.getFeatureID
            let i = Int(message.params.first ?? 0)
            answer.params = features.indices.contains(i) ? HIDPP.bigEndian(features[i]) + [0, 0] : [0, 0]
        default:
            guard let feature = HIDPP.FeatureID(rawValue: featureID),
                  let handler = handlers[Self.key(feature, message.function)] else { return error(message, 0x07) }
            answer.params = handler(message.params)
        }
        return answer
    }
}
