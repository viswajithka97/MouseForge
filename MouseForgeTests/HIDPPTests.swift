//
//  HIDPPTests.swift
//  MouseForgeTests
//
//  HID++ message format, request/response matching, feature discovery and
//  every typed feature, against a simulated device.
//

import XCTest
@testable import MouseForge

final class HIDPPMessageTests: XCTestCase {
    func testEncodeLongReport() {
        let message = HIDPP.Message(deviceIndex: 0xFF, featureIndex: 0x05, function: 3, softwareID: 0xA, params: [0x01, 0x02])
        XCTAssertEqual(message.bytes.count, 20)
        XCTAssertEqual(Array(message.bytes.prefix(6)), [0x11, 0xFF, 0x05, 0x3A, 0x01, 0x02])
        XCTAssertEqual(HIDPP.Message(bytes: message.bytes)?.function, 3)
        XCTAssertEqual(HIDPP.Message(bytes: message.bytes)?.softwareID, 0xA)
    }

    func testShortReport() {
        let message = HIDPP.Message(reportID: HIDPP.shortReportID, deviceIndex: 1, featureIndex: 0, function: 1, softwareID: 1)
        XCTAssertEqual(message.bytes.count, 7)
    }

    func testErrorInfo() {
        let bytes: [UInt8] = [0x11, 0xFF, 0xFF, 0x05, 0x31, 0x02] + Array(repeating: 0, count: 14)
        let message = HIDPP.Message(bytes: bytes)!
        XCTAssertTrue(message.isError)
        XCTAssertEqual(message.errorInfo?.featureIndex, 0x05)
        XCTAssertEqual(message.errorInfo?.code, 0x02)
    }

    func testRejectsNonHIDPPReports() {
        XCTAssertNil(HIDPP.Message(bytes: [0x02, 0, 0, 0]))
        XCTAssertNil(HIDPP.Message(bytes: [0x11]))
    }

    func testFeatureNames() {
        XCTAssertEqual(HIDPP.featureName(0x2201), "Adjustable DPI")
        XCTAssertEqual(HIDPP.featureName(0x1234), "Feature 0x1234")
    }
}

final class HIDPPChannelTests: XCTestCase {
    func testRequestGetsMatchingReply() async throws {
        let fake = FakeHIDPPDevice()
        let channel = HIDPPChannel(transport: fake)
        let reply = try await channel.request(device: 0xFF, featureIndex: 0, function: 1, params: [0, 0, 0x77])
        XCTAssertEqual(Array(reply.prefix(3)), [4, 5, 0x77])
    }

    func testDeviceErrorIsThrown() async {
        let fake = FakeHIDPPDevice()
        let channel = HIDPPChannel(transport: fake)
        do {
            _ = try await channel.request(device: 0xFF, featureIndex: 1, function: 9)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? HIDPP.Failure, .deviceError(0x07))
        }
    }

    func testTimeout() async {
        let fake = FakeHIDPPDevice()
        fake.silent = true
        let channel = HIDPPChannel(transport: fake)
        do {
            _ = try await channel.request(device: 0xFF, featureIndex: 0, function: 1, timeout: 0.1)
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? HIDPP.Failure, .timeout)
        }
    }

    func testConcurrentRequestsAreSerialized() async throws {
        let fake = FakeHIDPPDevice()
        fake.on(.deviceName, 0) { _ in [9] }
        let channel = HIDPPChannel(transport: fake)
        async let a = channel.request(device: 0xFF, featureIndex: 0, function: 1, params: [0, 0, 1])
        async let b = channel.request(device: 0xFF, featureIndex: 0, function: 1, params: [0, 0, 2])
        let (ra, rb) = try await (a, b)
        XCTAssertEqual(ra[2], 1)
        XCTAssertEqual(rb[2], 2)
        // Each request used its own software id.
        XCTAssertNotEqual(fake.sent[0].softwareID, fake.sent[1].softwareID)
        XCTAssertTrue(fake.sent.allSatisfy { (1...15).contains($0.softwareID) })
    }

    func testUnsolicitedMessagesAreNotifications() async throws {
        let fake = FakeHIDPPDevice()
        let channel = HIDPPChannel(transport: fake)
        let received = expectation(description: "notification")
        channel.onNotification = { message in
            if message.featureIndex == 3 { received.fulfill() }
        }
        fake.push(HIDPP.Message(deviceIndex: 0xFF, featureIndex: 3, function: 0, softwareID: 0, params: [50, 4, 0]))
        await fulfillment(of: [received], timeout: 1)
    }

    func testLateReplyIsNotTreatedAsEvent() async {
        let fake = FakeHIDPPDevice()
        let channel = HIDPPChannel(transport: fake)
        var events: [HIDPP.Message] = []
        channel.onNotification = { events.append($0) }
        // A reply (software id 5) nobody asked for, and a real event (software id 0).
        fake.push(HIDPP.Message(deviceIndex: 0xFF, featureIndex: 4, function: 0, softwareID: 5, params: [3]))
        fake.push(HIDPP.Message(deviceIndex: 0xFF, featureIndex: 4, function: 0, softwareID: 0, params: [0, 0xC3]))
        // A receiver connection notification keeps its own byte layout.
        fake.push(HIDPP.Message(reportID: HIDPP.shortReportID, deviceIndex: 1, featureIndex: 0x41, function: 0, softwareID: 4, params: [0x40]))
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(events.map(\.softwareID).sorted(), [0, 4])
    }

    func testEmptyReceiverSlotFailsPing() async {
        let fake = FakeHIDPPDevice()
        fake.presentIndexes = [2]
        let channel = HIDPPChannel(transport: fake)
        let empty = HIDPPDevice(channel: channel, index: 1)
        let present = HIDPPDevice(channel: channel, index: 2)
        do {
            try await empty.ping()
            XCTFail("empty slot answered")
        } catch {}
        do {
            try await present.ping()
        } catch {
            XCTFail("paired device didn't answer: \(error)")
        }
    }
}

final class HIDPPDeviceTests: XCTestCase {
    private func device(_ configure: (FakeHIDPPDevice) -> Void) async throws -> (HIDPPDevice, FakeHIDPPDevice) {
        let fake = FakeHIDPPDevice()
        configure(fake)
        let device = HIDPPDevice(channel: HIDPPChannel(transport: fake), index: 0xFF)
        try await device.ping()
        try await device.discoverFeatures()
        return (device, fake)
    }

    func testDiscovery() async throws {
        let (device, _) = try await device { fake in
            fake.on(.deviceName, 0) { _ in [0] }
            fake.on(.adjustableDPI, 0) { _ in [1] }
        }
        XCTAssertTrue(device.has(.deviceName))
        XCTAssertTrue(device.has(.adjustableDPI))
        XCTAssertFalse(device.has(.thumbWheel))
        XCTAssertEqual(device.featureIDs, [0x0000, 0x0001, 0x0005, 0x2201])
        XCTAssertEqual(device.protocolVersion.major, 4)
    }

    func testNameInChunks() async throws {
        let name = Array("MX Master 3S Mouse".utf8)
        let (device, _) = try await device { fake in
            fake.on(.deviceName, 0) { _ in [UInt8(name.count)] }
            fake.on(.deviceName, 1) { params in
                let offset = Int(params[0])
                return Array(name[offset..<min(offset + 16, name.count)])
            }
        }
        let read = try await device.name()
        XCTAssertEqual(read, "MX Master 3S Mouse")
    }

    func testMissingFeatureThrows() async throws {
        let (device, _) = try await device { _ in }
        do {
            _ = try await device.battery()
            XCTFail("expected featureNotSupported")
        } catch {
            XCTAssertEqual(error as? HIDPP.Failure, .featureNotSupported(0x1004))
        }
    }

    func testUnifiedBattery() async throws {
        let (device, _) = try await device { fake in
            fake.on(.unifiedBattery, 1) { _ in [72, 0x04, 0, 0] }
        }
        let battery = try await device.battery()
        XCTAssertEqual(battery, BatteryInfo(percent: 72, level: .good, charging: .discharging))
        XCTAssertFalse(battery.isLow)
    }

    func testBatteryDecoders() {
        XCTAssertEqual(HIDPPDevice.decodeUnifiedBattery([10, 0x02, 1]).charging, .charging)
        XCTAssertFalse(HIDPPDevice.decodeUnifiedBattery([10, 0x02, 1]).isLow) // charging isn't "low"
        XCTAssertTrue(HIDPPDevice.decodeUnifiedBattery([10, 0x02, 0]).isLow)
        XCTAssertEqual(HIDPPDevice.decodeBatteryStatus([50, 20, 0]).percent, 50)
        XCTAssertEqual(HIDPPDevice.decodeBatteryStatus([90, 80, 3]).charging, .full)
        let voltage = HIDPPDevice.decodeBatteryVoltage(HIDPP.bigEndian(3811) + [0])
        XCTAssertEqual(voltage.percent, 50)
        XCTAssertEqual(HIDPPDevice.decodeBatteryVoltage(HIDPP.bigEndian(4200) + [0x80]).charging, .charging)
    }

    func testDPIListWithRange() {
        // 200, then step 50, up to 4000; then 0 terminator.
        let bytes = HIDPP.bigEndian(200) + HIDPP.bigEndian(0xE032) + HIDPP.bigEndian(4000) + [0, 0]
        let list = HIDPPDevice.decodeDPIList(bytes)
        XCTAssertTrue(list.complete)
        XCTAssertEqual(list.dpis.first, 200)
        XCTAssertEqual(list.dpis.last, 4000)
        XCTAssertEqual(list.dpis.count, 77)
    }

    func testDPIListOfValues() {
        let bytes: [UInt8] = [UInt16(400), 800, 1600, 3200].flatMap(HIDPP.bigEndian) + [0, 0]
        XCTAssertEqual(HIDPPDevice.decodeDPIList(bytes).dpis, [400, 800, 1600, 3200])
    }

    func testReadAndSetDPI() async throws {
        let (device, fake) = try await device { fake in
            fake.on(.adjustableDPI, 1) { _ in [0] + HIDPP.bigEndian(400) + HIDPP.bigEndian(0xE064) + HIDPP.bigEndian(8000) + [0, 0] }
            fake.on(.adjustableDPI, 2) { _ in [0] + HIDPP.bigEndian(0) + HIDPP.bigEndian(1000) } // 0 = default
            fake.on(.adjustableDPI, 3) { params in params }
        }
        let dpi = try await device.dpi()
        XCTAssertEqual(dpi.current, 1000)
        XCTAssertEqual(dpi.defaultDPI, 1000)
        XCTAssertEqual(dpi.nearest(1234), 1200)
        try await device.setDPI(1600)
        let set = try XCTUnwrap(fake.sent.last)
        XCTAssertEqual(set.function, 3)
        XCTAssertEqual(Array(set.params.prefix(3)), [0, 0x06, 0x40])
    }

    func testSmartShiftDecodeEncode() {
        XCTAssertEqual(SmartShiftInfo.decode([1, 10, 30], enhanced: false).mode, .freeSpin)
        XCTAssertEqual(SmartShiftInfo.decode([2, 255, 30], enhanced: false).mode, .ratchet)
        let auto = SmartShiftInfo.decode([2, 12, 30], enhanced: true)
        XCTAssertEqual(auto.mode, .smartShift)
        XCTAssertEqual(auto.sensitivity, 12)
        XCTAssertEqual(auto.encode(), [2, 12, 0])
        XCTAssertEqual(SmartShiftInfo(mode: .ratchet, sensitivity: 12, enhanced: false).encode(), [2, 255, 0])
        XCTAssertEqual(SmartShiftInfo(mode: .freeSpin, sensitivity: 12, enhanced: false).encode()[0], 1)
    }

    func testSmartShiftEnhancedUsesFunctionsOneAndTwo() async throws {
        let (device, fake) = try await device { fake in
            fake.on(.smartShiftEnhanced, 1) { _ in [2, 20, 30] }
            fake.on(.smartShiftEnhanced, 2) { params in params }
        }
        let info = try await device.smartShift()
        XCTAssertTrue(info.enhanced)
        try await device.setSmartShift(SmartShiftInfo(mode: .ratchet, sensitivity: 20, enhanced: true))
        XCTAssertEqual(fake.sent.last?.function, 2)
    }

    func testHiResFlags() {
        let info = HiResWheelInfo.decode(0x06)
        XCTAssertTrue(info.hiRes)
        XCTAssertTrue(info.inverted)
        XCTAssertFalse(info.diverted)
        var off = info
        off.hiRes = false
        XCTAssertEqual(off.flags, 0x04)
    }

    func testControlsAndDiversion() async throws {
        let (device, fake) = try await device { fake in
            fake.on(.reprogControlsV4, 0) { _ in [2] }
            fake.on(.reprogControlsV4, 1) { params in
                params[0] == 0
                    ? HIDPP.bigEndian(0x0053) + HIDPP.bigEndian(0x0038) + [0x31, 1, 1, 0, 0]
                    : HIDPP.bigEndian(0x00C3) + HIDPP.bigEndian(0x00A9) + [0x30, 0, 0, 0, 0x01]
            }
            fake.on(.reprogControlsV4, 2) { params in Array(params.prefix(2)) + [0, 0, 0] }
            fake.on(.reprogControlsV4, 3) { params in params }
        }
        let controls = try await device.controls()
        XCTAssertEqual(controls.map(\.cid), [0x0053, 0x00C3])
        XCTAssertEqual(controls[1].name, "Gesture Button")
        XCTAssertTrue(controls[1].isDivertable)
        XCTAssertTrue(controls[1].supportsRawXY)
        XCTAssertTrue(controls[0].isStandardButton)

        try await device.setDiverted(0x00C3, true)
        XCTAssertEqual(Array(try XCTUnwrap(fake.sent.last).params.prefix(3)), [0x00, 0xC3, 0x03])
        try await device.setDiverted(0x00C3, false)
        XCTAssertEqual(try XCTUnwrap(fake.sent.last).params[2], 0x02)
    }

    func testDivertedButtonEvent() {
        XCTAssertEqual(HIDPPDevice.decodeDivertedButtons(HIDPP.bigEndian(0x00C3) + [0, 0, 0, 0, 0, 0]), [0x00C3])
        XCTAssertEqual(HIDPPDevice.decodeDivertedButtons([UInt8](repeating: 0, count: 8)), [])
    }

    func testThumbWheel() async throws {
        let (device, fake) = try await device { fake in
            fake.on(.thumbWheel, 0) { _ in HIDPP.bigEndian(18) + HIDPP.bigEndian(120) + [0] }
            fake.on(.thumbWheel, 1) { _ in [1, 0] }
            fake.on(.thumbWheel, 2) { params in params }
        }
        let info = try await device.thumbWheel()
        XCTAssertEqual(info, ThumbWheelInfo(diverted: true, inverted: false, divertedResolution: 120))
        try await device.setThumbWheel(diverted: false, inverted: true)
        XCTAssertEqual(Array(try XCTUnwrap(fake.sent.last).params.prefix(2)), [0, 1])
        XCTAssertEqual(HIDPPDevice.decodeThumbWheelRotation(HIDPP.bigEndian(UInt16(bitPattern: -5))), -5)
    }

    func testEasySwitch() async throws {
        let (device, _) = try await device { fake in
            fake.on(.changeHost, 0) { _ in [3, 1] }
        }
        let host = try await device.hostInfo()
        XCTAssertEqual(host, HostInfo(count: 3, current: 1))
    }

    func testHaptics() async throws {
        let (device, fake) = try await device { fake in
            fake.on(.haptics, 0) { _ in [0, 0, 0x01, 0, 0, 0, 0x03, 0x01] }
            fake.on(.haptics, 1) { _ in [0x01, 75] }
            fake.on(.haptics, 2) { params in params }
            fake.on(.haptics, 4) { params in params }
        }
        let info = try await device.haptics()
        XCTAssertTrue(info.enabled)
        XCTAssertEqual(info.level, 75)
        XCTAssertTrue(info.levelsOnly)
        XCTAssertEqual(info.waveforms, [0, 8, 9])
        try await device.setHaptics(enabled: false, level: 50)
        XCTAssertEqual(Array(try XCTUnwrap(fake.sent.last).params.prefix(2)), [0, 50])
        try await device.playHaptic(0x08)
        XCTAssertEqual(fake.sent.last?.function, 4)
    }

    @MainActor
    func testLogitechDeviceRefreshHidesMissingFeatures() async throws {
        let (hidpp, _) = try await device { fake in
            fake.on(.unifiedBattery, 1) { _ in [55, 0x04, 0] }
        }
        let model = LogitechDevice(hidpp: hidpp, connection: .bolt)
        await model.refresh()
        XCTAssertEqual(model.battery?.percent, 55)
        XCTAssertNil(model.dpi)
        XCTAssertNil(model.smartShift)
        XCTAssertNil(model.haptics)
        XCTAssertTrue(model.controls.isEmpty)
    }

    @MainActor
    func testBatteryNotificationUpdatesModel() async throws {
        let (hidpp, _) = try await device { fake in
            fake.on(.unifiedBattery, 1) { _ in [55, 0x04, 0] }
        }
        let model = LogitechDevice(hidpp: hidpp, connection: .bluetooth)
        let index = try XCTUnwrap(hidpp.featureIndex(.unifiedBattery))
        let handled = model.apply(notification: HIDPP.Message(deviceIndex: 0xFF, featureIndex: index, function: 0, softwareID: 0, params: [9, 0x01, 0]))
        XCTAssertTrue(handled)
        XCTAssertEqual(model.battery?.percent, 9)
        XCTAssertTrue(model.battery?.isLow ?? false)
    }

    func testLogitechSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.logitech.dpiPresets = [1000, 2000]
        settings.logitech.hapticTicks = false
        let decoded = try SettingsStore.decode(try SettingsStore.encode(settings))
        XCTAssertEqual(decoded.logitech, settings.logitech)
    }
}
