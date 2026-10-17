//
//  MouseForgeApp.swift
//  MouseForge
//
//  Created by Viswajith on 17/10/26.
//

import SwiftUI

@main
struct MouseForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        // The menu-bar icon. LSUIElement = YES in the build settings hides
        // the Dock icon, so this is the app's only permanent UI.
        MenuBarExtra("MouseForge", systemImage: "computermouse") {
            MenuBarMenu(state: state, permissions: state.permissions, profiles: state.profiles, devices: state.devices)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Unit tests launch the app as their host; don't start the event tap
    /// or show windows then.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        MainActor.assumeIsolated {
            AppState.shared.launch()
            #if DEBUG
            DebugSnapshots.runIfRequested()
            #endif
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppState.shared.shutdown()
        }
    }
}
