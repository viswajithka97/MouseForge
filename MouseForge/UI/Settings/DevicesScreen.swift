//
//  DevicesScreen.swift
//  MouseForge
//
//  Every connected mouse, with Logitech devices (name, connection,
//  battery) first.
//

import SwiftUI

struct DevicesScreen: View {
    @ObservedObject var devices: DeviceManager
    @ObservedObject var permissions: PermissionsManager
    let openLogitech: () -> Void

    var body: some View {
        Form {
            if devices.needsInputMonitoring || !permissions.inputMonitoringGranted {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Input Monitoring is needed for Logitech features").font(.headline)
                            Text("Battery, DPI, SmartShift, and Logitech buttons need to talk to the mouse directly.")
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Grant Access…") { permissions.requestInputMonitoring() }
                                Button("Open System Settings") { permissions.openInputMonitoringSettings() }
                                if permissions.inputMonitoringRequested && !permissions.inputMonitoringGranted {
                                    Button("Relaunch MouseForge") { PermissionsManager.relaunch() }
                                }
                            }
                        }
                    }
                }
            }

            Section("Logitech") {
                if devices.logitechDevices.isEmpty {
                    Text("No Logitech device found. Connect one with a Logi Bolt or Unifying receiver, Bluetooth, or a cable.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(devices.logitechDevices) { device in
                        LogitechRow(device: device, open: openLogitech)
                    }
                }
            }

            Section("All Mice") {
                if devices.mice.isEmpty {
                    Text("No mouse connected.").foregroundStyle(.secondary)
                } else {
                    ForEach(devices.mice) { mouse in
                        HStack {
                            Image(systemName: "computermouse")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mouse.name)
                                Text([mouse.manufacturer, mouse.transport].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Text("Every mouse works with buttons, gestures, the Actions Ring, scrolling, and pointer settings. Extra buttons (6 and up) appear on the Buttons screen after you press them once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LogitechRow: View {
    @ObservedObject var device: LogitechDevice
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "computermouse.fill").font(.title2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.headline)
                HStack(spacing: 8) {
                    Text(device.connection.rawValue)
                    if let host = device.host {
                        Text("Easy-Switch channel \(host.current + 1) of \(host.count)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = device.battery {
                Label(battery.summary, systemImage: battery.symbol)
                    .foregroundStyle(battery.isLow ? .red : .secondary)
            }
            Button("Settings…", action: open)
        }
        .padding(.vertical, 2)
    }
}
