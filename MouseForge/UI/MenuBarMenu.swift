//
//  MenuBarMenu.swift
//  MouseForge
//
//  The drop-down menu shown when clicking the menu-bar icon.
//

import SwiftUI

struct MenuBarMenu: View {
    @ObservedObject var state: AppState
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var profiles: ProfileManager
    @ObservedObject var devices: DeviceManager

    var body: some View {
        Text(statusText)
        Text("Profile: \(profiles.activeProfileName)")
        ForEach(devices.logitechDevices) { device in
            DeviceMenuLine(device: device)
        }
        if devices.logitechDevices.isEmpty, let mouse = devices.mice.first {
            Text("Mouse: \(mouse.name)")
        }

        Divider()

        Toggle("Enable Remapping (⌃⌥⌘M)", isOn: $state.isEnabled)

        Button("Settings…") {
            WindowManager.shared.showSettings()
        }
        .keyboardShortcut(",")

        Button("Show Event Log…") {
            WindowManager.shared.showEventLog()
        }

        Button(permissions.allGranted ? "Permissions…" : "Permissions… (action needed)") {
            WindowManager.shared.showOnboarding()
        }

        Divider()

        Button("Quit MouseForge") {
            confirmQuit()
        }
        .keyboardShortcut("q")
    }

    /// Quitting turns every customization off, which surprises people who
    /// expect it to keep working in the background, so ask first.
    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit MouseForge?"
        alert.informativeText = "Your buttons, gestures, scrolling, and other customizations only work while MouseForge is running. To hide the window, just close it; MouseForge keeps working from the menu bar."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            AppDelegate.quit()
        }
    }

    private var statusText: String {
        switch state.tapStatus {
        case .running: return state.isEnabled ? "Status: Active" : "Status: Paused"
        case .waitingForPermission: return "Status: Needs Accessibility permission"
        case .failed: return "Status: Couldn't start (check permissions)"
        }
    }
}

private struct DeviceMenuLine: View {
    @ObservedObject var device: LogitechDevice

    var body: some View {
        let channel = device.host.map { "  ·  Channel \($0.current + 1)" } ?? ""
        if let battery = device.battery {
            Label("\(device.name) – \(battery.summary)\(channel)", systemImage: battery.symbol)
        } else {
            Text(device.name + channel)
        }
    }
}
