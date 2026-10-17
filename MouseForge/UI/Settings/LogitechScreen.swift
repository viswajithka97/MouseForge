//
//  LogitechScreen.swift
//  MouseForge
//
//  Settings stored in the Logitech device itself: DPI, SmartShift,
//  hi-res wheel, Easy-Switch, thumb wheel, extra buttons, haptics. Only
//  features the device reports are shown.
//

import SwiftUI

struct LogitechScreen: View {
    @ObservedObject var devices: DeviceManager
    @ObservedObject var store: SettingsStore
    @State private var selectedID: UUID?

    private var device: LogitechDevice? {
        devices.logitechDevices.first { $0.id == selectedID } ?? devices.logitechDevices.first
    }

    var body: some View {
        if let device {
            VStack(spacing: 0) {
                if devices.logitechDevices.count > 1 {
                    Picker("Device", selection: Binding(get: { device.id }, set: { selectedID = $0 })) {
                        ForEach(devices.logitechDevices) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding([.horizontal, .top], 16)
                }
                LogitechDeviceForm(device: device, store: store)
                    .id(device.id)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No Logitech device connected").font(.title3.weight(.semibold))
                Text("Connect a Logitech mouse with a Logi Bolt or Unifying receiver, Bluetooth, or a USB cable. Its battery, DPI, wheel, and button settings appear here.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
                if devices.needsInputMonitoring {
                    Text("MouseForge needs Input Monitoring permission to talk to Logitech devices (see Devices).")
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
        }
    }
}

struct LogitechDeviceForm: View {
    @ObservedObject var device: LogitechDevice
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Device", value: device.name)
                LabeledContent("Connection", value: device.connection.rawValue)
                if let battery = device.battery {
                    LabeledContent("Battery") {
                        Label(battery.summary, systemImage: battery.symbol)
                            .foregroundStyle(battery.isLow ? .red : .primary)
                    }
                    Toggle("Notify me when the battery is low", isOn: $store.settings.logitech.lowBatteryAlerts)
                }
                if let error = device.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }

            if let dpi = device.dpi {
                DPISection(device: device, dpi: dpi, store: store)
            }

            if device.smartShift != nil || device.hiResWheel != nil {
                WheelSection(device: device)
            }

            LogitechAdvancedSections(device: device, store: store)

            Section {
                DisclosureGroup("Supported HID++ features (\(device.features.count))") {
                    ForEach(device.features, id: \.self) { id in
                        LabeledContent(HIDPP.featureName(id), value: String(format: "0x%04X", id))
                            .font(.caption)
                    }
                    LabeledContent("Protocol", value: "HID++ \(device.protocolVersion)").font(.caption)
                }
                Button("Refresh") { Task { await device.refresh() } }
            }
        }
        .formStyle(.grouped)
    }
}

struct DPISection: View {
    @ObservedObject var device: LogitechDevice
    let dpi: DPIInfo
    @ObservedObject var store: SettingsStore
    @State private var pending: Double?

    var body: some View {
        Section {
            LabeledContent("Pointer DPI") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { pending ?? Double(dpi.supported.firstIndex(of: dpi.nearest(dpi.current)) ?? 0) },
                            set: { pending = $0 }
                        ),
                        in: 0...Double(max(dpi.supported.count - 1, 1)),
                        step: 1
                    ) { editing in
                        if !editing, let pending, dpi.supported.indices.contains(Int(pending)) {
                            let value = dpi.supported[Int(pending)]
                            self.pending = nil
                            Task { await device.setDPI(value) }
                        }
                    }
                    Text("\(displayed) DPI")
                        .monospacedDigit()
                        .frame(width: 90, alignment: .trailing)
                }
            }
            LabeledContent("Presets for Cycle DPI") {
                HStack(spacing: 6) {
                    ForEach(store.settings.logitech.dpiPresets.sorted(), id: \.self) { value in
                        Button {
                            Task { await device.setDPI(value) }
                        } label: {
                            Text("\(value)")
                        }
                        .contextMenu {
                            Button("Remove Preset") { store.settings.logitech.dpiPresets.removeAll { $0 == value } }
                        }
                        .help("Click to use now. Right-click to remove.")
                    }
                    Button {
                        let value = dpi.current
                        if !store.settings.logitech.dpiPresets.contains(value) {
                            store.settings.logitech.dpiPresets.append(value)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add the current DPI as a preset")
                }
            }
        } header: {
            Text("DPI")
        } footer: {
            Text("Assign “Cycle DPI” to a button to step through the presets. Default for this mouse: \(dpi.defaultDPI) DPI.")
                .foregroundStyle(.secondary)
        }
    }

    private var displayed: Int {
        if let pending, dpi.supported.indices.contains(Int(pending)) { return dpi.supported[Int(pending)] }
        return dpi.current
    }
}

private struct WheelSection: View {
    @ObservedObject var device: LogitechDevice

    var body: some View {
        Section("Scroll Wheel") {
            if let smartShift = device.smartShift {
                Picker("Wheel mode", selection: Binding(
                    get: { smartShift.mode },
                    set: { mode in
                        var info = smartShift
                        info.mode = mode
                        Task { await device.setSmartShift(info) }
                    }
                )) {
                    ForEach(SmartShiftInfo.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if smartShift.mode == .smartShift {
                    LabeledContent("SmartShift sensitivity") {
                        HStack {
                            Text("Switches easily").font(.caption).foregroundStyle(.secondary)
                            SensitivitySlider(device: device, info: smartShift)
                            Text("Rarely").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let hiRes = device.hiResWheel {
                Toggle("High-resolution scrolling", isOn: Binding(
                    get: { hiRes.hiRes },
                    set: { on in
                        var info = hiRes
                        info.hiRes = on
                        Task { await device.setHiResWheel(info) }
                    }
                ))
            }
        }
    }
}

/// Live-editing slider that only writes to the device when released.
private struct SensitivitySlider: View {
    @ObservedObject var device: LogitechDevice
    let info: SmartShiftInfo
    @State private var value: Double?

    var body: some View {
        Slider(
            value: Binding(get: { value ?? Double(info.sensitivity) }, set: { value = $0 }),
            in: Double(SmartShiftInfo.sensitivityRange.lowerBound)...Double(SmartShiftInfo.sensitivityRange.upperBound),
            step: 1
        ) { editing in
            guard !editing, let value else { return }
            var updated = info
            updated.sensitivity = Int(value)
            self.value = nil
            Task { await device.setSmartShift(updated) }
        }
    }
}

/// Easy-Switch, extra buttons, thumb wheel, and haptics.
struct LogitechAdvancedSections: View {
    @ObservedObject var device: LogitechDevice
    @ObservedObject var store: SettingsStore

    private var extraControls: [ControlInfo] {
        device.controls.filter { $0.isDivertable && !$0.isStandardButton }
    }

    var body: some View {
        if let host = device.host, host.count > 0 {
            Section("Easy-Switch") {
                HStack(spacing: 10) {
                    ForEach(0..<host.count, id: \.self) { channel in
                        VStack(spacing: 2) {
                            Text("\(channel + 1)")
                                .font(.title3.weight(.semibold))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(channel == host.current ? Color.accentColor : Color.primary.opacity(0.08)))
                                .foregroundStyle(channel == host.current ? Color.white : Color.primary)
                            Text(channel == host.current ? "This Mac" : "Channel \(channel + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Spacer()
                }
            }
        }

        if !extraControls.isEmpty {
            Section {
                Toggle("Let MouseForge handle extra buttons", isOn: $store.settings.logitech.divertControls)
                ForEach(extraControls) { control in
                    HStack {
                        Text(control.name)
                        Spacer()
                        Text(control.diverted ? "Handled by MouseForge" : "Not assigned")
                            .font(.caption)
                            .foregroundStyle(control.diverted ? Color.green : Color.secondary)
                        Button("Configure…") {
                            WindowManager.shared.showSettings(section: .buttons)
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Extra Buttons")
            } footer: {
                Text("A button is taken over only while some profile gives it an action (set it on the Buttons or Gestures screen). Everything is handed back when MouseForge quits.")
                    .foregroundStyle(.secondary)
            }
        }

        if let thumb = device.thumbWheel {
            Section {
                LabeledContent("Status", value: thumb.diverted ? "Handled by MouseForge" : "Native horizontal scrolling")
                Toggle("Let MouseForge handle the thumb wheel when needed", isOn: $store.settings.logitech.divertThumbWheel)
                Button("Thumb Wheel Settings…") {
                    WindowManager.shared.showSettings(section: .scrolling)
                }
            } header: {
                Text("Thumb Wheel")
            } footer: {
                Text("Plain horizontal scrolling stays native. Zoom, tabs, volume, brightness, timeline, and custom actions (set per app on the Scrolling screen) use MouseForge.")
                    .foregroundStyle(.secondary)
            }
        }

        if let haptics = device.haptics {
            Section {
                Toggle("Haptic feedback", isOn: Binding(
                    get: { haptics.enabled },
                    set: { on in Task { await device.setHaptics(enabled: on, level: haptics.level) } }
                ))
                if haptics.enabled {
                    if haptics.levelsOnly {
                        Picker("Intensity", selection: Binding(
                            get: { HapticsInfo.levelSteps.min { abs($0 - haptics.level) < abs($1 - haptics.level) } ?? 50 },
                            set: { level in Task { await device.setHaptics(enabled: true, level: level) } }
                        )) {
                            Text("Low").tag(25)
                            Text("Medium").tag(50)
                            Text("High").tag(75)
                            Text("Maximum").tag(100)
                        }
                        .pickerStyle(.segmented)
                    } else {
                        HapticLevelSlider(device: device, haptics: haptics)
                    }
                    Toggle("Tick when pointing at Actions Ring slots and on gestures", isOn: $store.settings.logitech.hapticTicks)
                    Button("Test") {
                        let waveform = haptics.waveforms.first ?? 0
                        Task { try? await device.hidpp.playHaptic(waveform) }
                    }
                }
            } header: {
                Text("Haptics")
            }
        }
    }
}

private struct HapticLevelSlider: View {
    @ObservedObject var device: LogitechDevice
    let haptics: HapticsInfo
    @State private var value: Double?

    var body: some View {
        LabeledContent("Intensity") {
            Slider(
                value: Binding(get: { value ?? Double(haptics.level) }, set: { value = $0 }),
                in: 1...100, step: 1
            ) { editing in
                guard !editing, let value else { return }
                self.value = nil
                Task { await device.setHaptics(enabled: true, level: Int(value)) }
            }
        }
    }
}
