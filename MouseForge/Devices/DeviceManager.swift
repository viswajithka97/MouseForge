//
//  DeviceManager.swift
//  MouseForge
//
//  Finds mice. Two IOHIDManagers run on a dedicated thread:
//  - every mouse (for the Devices list; only properties are read),
//  - Logitech HID++ interfaces (Bolt / Unifying receivers and devices on
//    Bluetooth or USB), which are opened to talk HID++.
//  Paired devices behind a receiver are found by pinging slots 1–6; the
//  receiver also announces devices connecting later.
//

import AppKit
import Combine
import IOKit.hid
import os
import UserNotifications

@MainActor
final class DeviceManager: ObservableObject {
    struct Mouse: Identifiable, Equatable {
        let id: String
        let name: String
        let manufacturer: String
        let transport: String
        let isLogitech: Bool
    }

    @Published private(set) var logitechDevices: [LogitechDevice] = []
    @Published private(set) var mice: [Mouse] = []
    /// A Logitech interface couldn't be opened for lack of permission.
    @Published private(set) var needsInputMonitoring = false

    /// Called when a diverted Logitech control changes, e.g. the gesture
    /// button (set by LogitechIntegration).
    var onDivertedButtons: ((LogitechDevice, Set<UInt16>) -> Void)?
    /// Called with thumb-wheel rotation while it is diverted.
    var onThumbWheel: ((LogitechDevice, Int) -> Void)?
    /// Called when the set of devices or their controls changes.
    var onDevicesChanged: (() -> Void)?

    static let logitechVendorID = 0x046D
    /// Product IDs of Logitech receivers (others are direct devices).
    static let boltReceivers: Set<Int> = [0xC548]
    static let unifyingReceivers: Set<Int> = [0xC52B, 0xC532, 0xC534, 0xC539, 0xC53A, 0xC53D, 0xC53F, 0xC547]

    private let logger = Logger(subsystem: "com.mouse.forge.MouseForge", category: "Devices")
    private var hidThread: Thread?
    private var hidRunLoop: CFRunLoop?
    private var miceManager: IOHIDManager?
    private var logitechManager: IOHIDManager?

    private final class Interface {
        let transport: IOHIDTransport
        let channel: HIDPPChannel
        let connection: LogitechConnection
        let isReceiver: Bool
        var devices: [UInt8: LogitechDevice] = [:]

        init(transport: IOHIDTransport, connection: LogitechConnection, isReceiver: Bool) {
            self.transport = transport
            self.channel = HIDPPChannel(transport: transport)
            self.connection = connection
            self.isReceiver = isReceiver
        }
    }

    private var interfaces: [ObjectIdentifier: Interface] = [:]
    private var lowBatteryNotified: Set<UUID> = []
    private var batteryTimer: Timer?
    private var mouseDevices: [IOHIDDevice] = []

    // MARK: - Start

    func start() {
        guard hidThread == nil else { return }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.setUpManagers(on: runLoop!) }
            }
            ready.signal()
            // Keep the run loop alive even before devices appear.
            let port = NSMachPort()
            RunLoop.current.add(port, forMode: .default)
            CFRunLoopRun()
        }
        thread.name = "MouseForge.HID"
        thread.qualityOfService = .userInitiated
        hidThread = thread
        thread.start()
        ready.wait()

        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBatteries() }
        }
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
    }

    private func setUpManagers(on runLoop: CFRunLoop) {
        hidRunLoop = runLoop
        let context = Unmanaged.passUnretained(self).toOpaque()

        let mice = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mice, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse,
        ] as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(mice, miceChangedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(mice, miceChangedCallback, context)
        IOHIDManagerScheduleWithRunLoop(mice, runLoop, CFRunLoopMode.defaultMode.rawValue)
        miceManager = mice

        let logitech = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(logitech, [
            [kIOHIDVendorIDKey: Self.logitechVendorID, kIOHIDDeviceUsagePageKey: 0xFF00],
            [kIOHIDVendorIDKey: Self.logitechVendorID, kIOHIDDeviceUsagePageKey: 0xFF43],
        ] as CFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(logitech, logitechAddedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(logitech, logitechRemovedCallback, context)
        IOHIDManagerScheduleWithRunLoop(logitech, runLoop, CFRunLoopMode.defaultMode.rawValue)
        logitechManager = logitech

        // Matching callbacks for already-connected devices arrive once the
        // managers are scheduled; opening the managers themselves isn't
        // needed (each Logitech device is opened on its own).
        updateMiceList()
    }

    // MARK: - Mice list

    fileprivate func updateMiceList() {
        guard let miceManager else { return }
        let devices = (IOHIDManagerCopyDevices(miceManager) as? Set<IOHIDDevice>) ?? []
        var list: [Mouse] = []
        var seen = Set<String>()
        for device in devices {
            func string(_ key: String) -> String? { IOHIDDeviceGetProperty(device, key as CFString) as? String }
            func int(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
            let name = string(kIOHIDProductKey) ?? "Mouse"
            let vendor = int(kIOHIDVendorIDKey)
            let product = int(kIOHIDProductIDKey)
            let transport = string(kIOHIDTransportKey) ?? ""
            // Skip trackpads; they aren't mice.
            if name.localizedCaseInsensitiveContains("trackpad") { continue }
            let key = "\(vendor)-\(product)-\(name)-\(transport)"
            guard seen.insert(key).inserted else { continue }
            list.append(Mouse(
                id: key, name: name,
                manufacturer: string(kIOHIDManufacturerKey) ?? "",
                transport: transport,
                isLogitech: vendor == Self.logitechVendorID
            ))
        }
        list.sort { $0.name < $1.name }
        if list != mice { mice = list }
        // A mouse came or went: custom pointer settings need re-applying.
        AppState.shared.pointer.reapply()
    }

    // MARK: - Logitech interfaces

    fileprivate func logitechAdded(_ device: IOHIDDevice) {
        let transport = IOHIDTransport(device: device)
        let result = transport.open()
        guard result == kIOReturnSuccess else {
            if result == kIOReturnNotPermitted { needsInputMonitoring = true }
            logger.error("Couldn't open Logitech interface: \(result)")
            return
        }
        needsInputMonitoring = false

        let productID = transport.intProperty(kIOHIDProductIDKey) ?? 0
        let transportName = transport.stringProperty(kIOHIDTransportKey) ?? ""
        let connection: LogitechConnection
        let isReceiver: Bool
        if Self.boltReceivers.contains(productID) {
            (connection, isReceiver) = (.bolt, true)
        } else if Self.unifyingReceivers.contains(productID) {
            (connection, isReceiver) = (.unifying, true)
        } else if transportName.localizedCaseInsensitiveContains("bluetooth") {
            (connection, isReceiver) = (.bluetooth, false)
        } else {
            (connection, isReceiver) = (.usb, false)
        }

        let interface = Interface(transport: transport, connection: connection, isReceiver: isReceiver)
        interfaces[ObjectIdentifier(device)] = interface
        interface.channel.onNotification = { [weak self, weak interface] message in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let interface else { return }
                    self.handle(message, on: interface)
                }
            }
        }

        Task {
            if isReceiver {
                // Ask the receiver to announce devices that connect later
                // (HID++ 1.0 register 0x00, "wireless notifications").
                try? transport.send([HIDPP.shortReportID, HIDPP.directDeviceIndex, 0x80, 0x00, 0x00, 0x01, 0x00])
                for index in UInt8(1)...6 {
                    await probe(interface, index: index)
                }
            } else {
                await probe(interface, index: HIDPP.directDeviceIndex)
            }
        }
    }

    fileprivate func logitechRemoved(_ device: IOHIDDevice) {
        guard let interface = interfaces.removeValue(forKey: ObjectIdentifier(device)) else { return }
        for device in interface.devices.values {
            onDivertedButtons?(device, [])
        }
        interface.channel.cancelAll()
        interface.transport.close()
        // A report already queued on the HID thread may still reference the
        // transport and its buffer; keep them alive a little longer.
        let transport = interface.transport
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { _ = transport }
        let removed = Set(interface.devices.values.map(\.id))
        logitechDevices.removeAll { removed.contains($0.id) }
        onDevicesChanged?()
    }

    private func probe(_ interface: Interface, index: UInt8) async {
        let hidpp = HIDPPDevice(channel: interface.channel, index: index)
        do {
            try await hidpp.ping(timeout: interface.isReceiver ? 0.8 : 2)
            try await hidpp.discoverFeatures()
        } catch {
            return // Empty slot, asleep, or not HID++ 2.0.
        }
        let device = LogitechDevice(hidpp: hidpp, connection: interface.connection)
        await device.refresh()
        if let old = interface.devices[index] {
            onDivertedButtons?(old, [])
            logitechDevices.removeAll { $0.id == old.id }
        }
        interface.devices[index] = device
        logitechDevices.append(device)
        logger.info("Found \(device.name, privacy: .public) via \(interface.connection.rawValue, privacy: .public)")
        checkBattery(device)
        onDevicesChanged?()
    }

    private func handle(_ message: HIDPP.Message, on interface: Interface) {
        // Receiver: a paired device connected or disconnected.
        if interface.isReceiver, message.featureIndex == HIDPP.deviceConnectionSubID {
            let disconnected = message.bytes.count > 4 && message.bytes[4] & 0x40 != 0
            if disconnected, let device = interface.devices[message.deviceIndex] {
                // Anything held on it will never report a release.
                onDivertedButtons?(device, [])
            }
            if !disconnected {
                let index = message.deviceIndex
                Task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    await probe(interface, index: index)
                }
            }
            return
        }
        guard let device = interface.devices[message.deviceIndex] else { return }
        if device.apply(notification: message) {
            checkBattery(device)
            return
        }
        guard message.function == 0, let feature = device.hidpp.feature(at: message.featureIndex) else { return }
        switch HIDPP.FeatureID(rawValue: feature) {
        case .reprogControlsV4:
            onDivertedButtons?(device, HIDPPDevice.decodeDivertedButtons(message.params))
        case .thumbWheel:
            onThumbWheel?(device, HIDPPDevice.decodeThumbWheelRotation(message.params))
        default:
            break
        }
    }

    // MARK: - Battery

    private func refreshBatteries() {
        for device in logitechDevices {
            Task {
                await device.refreshBattery()
                checkBattery(device)
            }
        }
    }

    private func checkBattery(_ device: LogitechDevice) {
        guard let battery = device.battery else { return }
        guard battery.isLow else {
            lowBatteryNotified.remove(device.id)
            return
        }
        guard AppState.shared.store.settings.logitech.lowBatteryAlerts,
              lowBatteryNotified.insert(device.id).inserted else { return }
        Self.notifyLowBattery(name: device.name, battery: battery)
    }

    private static func notifyLowBattery(name: String, battery: BatteryInfo) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = "\(name) battery low"
            content.body = "Battery at \(battery.summary). Charge it soon."
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "battery-\(name)", content: content, trigger: nil))
        }
    }

    // MARK: - DPI cycle

    /// Moves every Logitech mouse with adjustable DPI to the next preset.
    func cycleDPI() {
        let presets = AppState.shared.store.settings.logitech.dpiPresets.sorted()
        let candidates = logitechDevices.filter { $0.dpi != nil }
        guard !presets.isEmpty, !candidates.isEmpty else {
            StatusHUD.show(symbol: "gauge.with.dots.needle.33percent", title: "No adjustable DPI", subtitle: "Connect a Logitech mouse")
            return
        }
        for device in candidates {
            guard let info = device.dpi else { continue }
            let values = Array(Set(presets.map(info.nearest))).sorted()
            let next = values.first { $0 > info.current } ?? values[0]
            Task {
                await device.setDPI(next)
                StatusHUD.show(symbol: "gauge.with.dots.needle.33percent", title: "\(next) DPI", subtitle: device.name)
            }
        }
    }

    /// The device to show in the menu bar.
    var primaryDevice: LogitechDevice? {
        logitechDevices.first { $0.battery != nil } ?? logitechDevices.first
    }
}

// MARK: - IOKit callbacks (HID thread)

private func miceChangedCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else { return }
    let manager = Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated { manager.updateMiceList() }
    }
}

private func logitechAddedCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else { return }
    let manager = Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue()
    // Devices stay scheduled on the HID thread's run loop, so their input
    // reports arrive there; setup happens on the main actor.
    DispatchQueue.main.async {
        MainActor.assumeIsolated { manager.logitechAdded(device) }
    }
}

private func logitechRemovedCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else { return }
    let manager = Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated { manager.logitechRemoved(device) }
    }
}
