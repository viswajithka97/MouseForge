//
//  PointerScreen.swift
//  MouseForge
//
//  Pointer speed and acceleration for mice. Logitech DPI controls appear
//  here too when a mouse supports them.
//

import SwiftUI

struct PointerScreen: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var pointer: PointerEngine
    @ObservedObject var devices: DeviceManager

    private var settings: Binding<PointerSettings> { $store.settings.pointer }

    var body: some View {
        Form {
            Section {
                Picker("Pointer settings", selection: settings.mode) {
                    Text("Use macOS settings").tag(PointerSettings.Mode.system)
                    Text("Custom (MouseForge)").tag(PointerSettings.Mode.custom)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Custom settings apply to mice only, never trackpads, and are undone when you switch back or quit MouseForge.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Pointer acceleration", isOn: settings.accelerationEnabled)
                if settings.wrappedValue.accelerationEnabled {
                    LabeledContent("Tracking speed") {
                        HStack {
                            Text("Slow").font(.caption).foregroundStyle(.secondary)
                            Slider(value: settings.acceleration, in: PointerSettings.accelerationRange)
                            Text("Fast").font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f", settings.wrappedValue.acceleration))
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    HStack {
                        Text("Presets:").foregroundStyle(.secondary)
                        ForEach([("Slow", 0.3), ("macOS Default", 0.6875), ("macOS Max", 3.0), ("Very Fast", 5.0)], id: \.0) { name, value in
                            Button(name) { settings.wrappedValue.acceleration = value }
                                .controlSize(.small)
                        }
                    }
                } else {
                    Text("Off: the pointer moves the same distance for the same hand movement, however fast you move (best for precise work and games). To change how far that is, use your mouse's DPI button or a Logitech DPI setting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Speed & Acceleration")
            } footer: {
                Text("Tracking speed is the same setting as System Settings ▸ Mouse ▸ Tracking speed, but goes beyond its maximum (3) up to 5. Higher values also mean stronger acceleration; macOS combines the two.")
                    .foregroundStyle(.secondary)
            }
            .disabled(settings.wrappedValue.mode == .system)

            ForEach(devices.logitechDevices) { device in
                LogitechDPIRow(device: device, store: store)
            }

            Section("Mice") {
                if pointer.mice.isEmpty {
                    Text("No mouse connected.").foregroundStyle(.secondary)
                } else {
                    ForEach(pointer.mice) { mouse in
                        Label(mouse.name, systemImage: "computermouse")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { DispatchQueue.main.async { pointer.reapply() } }
    }
}

/// DPI controls for a Logitech mouse that supports them.
private struct LogitechDPIRow: View {
    @ObservedObject var device: LogitechDevice
    @ObservedObject var store: SettingsStore

    var body: some View {
        if let dpi = device.dpi {
            DPISection(device: device, dpi: dpi, store: store)
        }
    }
}
