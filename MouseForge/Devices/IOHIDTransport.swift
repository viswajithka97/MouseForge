//
//  IOHIDTransport.swift
//  MouseForge
//
//  HID++ over a real IOHIDDevice: output reports go out with
//  IOHIDDeviceSetReport, input reports arrive through a callback on the
//  thread whose run loop the device is scheduled on.
//

import Foundation
import IOKit.hid

final class IOHIDTransport: HIDPPTransport, @unchecked Sendable {
    let device: IOHIDDevice
    var onReport: (([UInt8]) -> Void)?

    private let bufferSize = 64
    private let buffer: UnsafeMutablePointer<UInt8>
    private var isOpen = false

    init(device: IOHIDDevice) {
        self.device = device
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit {
        buffer.deallocate()
    }

    /// Opens the device and starts listening. Returns the IOKit result
    /// (kIOReturnNotPermitted means Input Monitoring is missing).
    func open() -> IOReturn {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { return result }
        isOpen = true
        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, bufferSize, transportReportCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        return result
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func send(_ report: [UInt8]) throws {
        guard isOpen, let reportID = report.first else { throw HIDPP.Failure.disconnected }
        let result = report.withUnsafeBufferPointer { pointer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), pointer.baseAddress!, pointer.count)
        }
        guard result == kIOReturnSuccess else { throw HIDPP.Failure.sendFailed(result) }
    }

    fileprivate func received(reportID: UInt32, bytes: UnsafeMutablePointer<UInt8>, length: Int) {
        var data = Array(UnsafeBufferPointer(start: bytes, count: length))
        // Some paths deliver the report without its ID byte.
        if data.first != UInt8(truncatingIfNeeded: reportID) {
            data.insert(UInt8(truncatingIfNeeded: reportID), at: 0)
        }
        onReport?(data)
    }

    // MARK: - Properties

    func intProperty(_ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    func stringProperty(_ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }
}

private func transportReportCallback(
    context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex
) {
    guard let context, result == kIOReturnSuccess else { return }
    let transport = Unmanaged<IOHIDTransport>.fromOpaque(context).takeUnretainedValue()
    transport.received(reportID: reportID, bytes: report, length: reportLength)
}
