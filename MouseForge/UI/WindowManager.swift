//
//  WindowManager.swift
//  MouseForge
//
//  Opens and reuses the app's windows. Menu-bar apps have no Dock icon, so
//  we must explicitly bring the app to the front when showing a window.
//

import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var onboardingWindow: NSWindow?
    private var eventLogWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var testAreaWindow: NSWindow?

    private init() {}

    func showOnboarding() {
        let state = AppState.shared
        state.permissions.refresh()
        show(
            &onboardingWindow,
            title: "Welcome to MouseForge",
            view: OnboardingView(state: state, permissions: state.permissions)
        )
    }

    func closeOnboarding() {
        onboardingWindow?.close()
    }

    func showEventLog() {
        let state = AppState.shared
        show(
            &eventLogWindow,
            title: "MouseForge Event Log",
            view: EventLogView(state: state, model: EventLogModel(log: state.engine.log))
        )
    }

    func showSettings(section: SettingsSection? = nil, selectedApp: String?? = nil) {
        let navigation = SettingsNavigation.shared
        if let section { navigation.section = section }
        if let selectedApp { navigation.selectedApp = selectedApp }
        let isNew = settingsWindow == nil
        show(&settingsWindow, title: "MouseForge Settings", view: SettingsView(state: AppState.shared))
        if isNew, let window = settingsWindow {
            window.setContentSize(NSSize(width: 1060, height: 700))
            window.center()
            window.setFrameAutosaveName("MouseForgeSettings")
        }
    }

    func showTestArea() {
        let state = AppState.shared
        let isNew = testAreaWindow == nil
        show(
            &testAreaWindow,
            title: "MouseForge Test Area",
            view: TestAreaView(state: state, model: TestAreaModel(activity: state.engine.activity)) { [weak self] in
                self?.testAreaWindow?.close()
            }
        )
        if isNew { testAreaWindow?.setContentSize(NSSize(width: 1000, height: 600)) }
    }

    var settingsWindowForDebug: NSWindow? { settingsWindow }

    private func show<Content: View>(_ window: inout NSWindow?, title: String, view: Content) {
        if window == nil {
            let newWindow = NSWindow(contentViewController: NSHostingController(rootView: view))
            newWindow.title = title
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
