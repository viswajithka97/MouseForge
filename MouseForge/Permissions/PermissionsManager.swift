//
//  PermissionsManager.swift
//  MouseForge
//
//  Tracks the two privacy permissions MouseForge needs:
//  - Accessibility: required for an active CGEventTap (seeing and changing
//    mouse events) and for window actions.
//  - Input Monitoring: required to talk to Logitech mice over HID++.
//
//  Checking never prompts. The prompting APIs are only called when the user
//  clicks "Grant Access…" in onboarding. macOS has no "permission changed"
//  callback, so we poll once a second while something is still missing.
//

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import IOKit.hid

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var inputMonitoringGranted = false
    /// The user asked for Input Monitoring in this run. macOS often only
    /// reports the new state after a relaunch, so onboarding then offers one.
    @Published private(set) var inputMonitoringRequested = false

    var allGranted: Bool { accessibilityGranted && inputMonitoringGranted }

    private var pollTimer: Timer?

    init() {
        refresh()
    }

    /// Non-prompting checks only.
    func refresh() {
        let ax = AXIsProcessTrusted()
        let im = CGPreflightListenEventAccess()
        if ax != accessibilityGranted { accessibilityGranted = ax }
        if im != inputMonitoringGranted { inputMonitoringGranted = im }
        updatePolling()
    }

    /// Shows the system "MouseForge would like to control this computer"
    /// prompt (only the first time) and adds MouseForge to the list in
    /// System Settings, switched off. The user still has to flip the switch.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    /// Shows the system Input Monitoring prompt (only the first time).
    /// Asks through both the HID and CoreGraphics APIs (either one is what
    /// adds MouseForge to the list, depending on the macOS version), then
    /// opens the Input Monitoring page so the user can flip the switch.
    func requestInputMonitoring() {
        inputMonitoringRequested = true
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        _ = CGRequestListenEventAccess()
        refresh()
        if !inputMonitoringGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.openInputMonitoringSettings()
            }
        }
    }

    /// For adding MouseForge by hand: drag it into the list, or use "+".
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openPrivacyPane("Privacy_ListenEvent")
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updatePolling() {
        if allGranted {
            pollTimer?.invalidate()
            pollTimer = nil
        } else if pollTimer == nil {
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
    }

    /// Starts a fresh copy of the app and quits this one. Used when macOS
    /// only applies a newly granted permission to new processes.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this process to exit, then reopen the app.
        task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"\(path)\""]
        try? task.run()
        AppDelegate.quit()
    }
}
