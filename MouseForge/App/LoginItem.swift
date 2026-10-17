//
//  LoginItem.swift
//  MouseForge
//
//  Launch at login via SMAppService (macOS 13+). The status can also be
//  changed by the user in System Settings ▸ General ▸ Login Items, so it's
//  re-read whenever the UI shows it.
//

import Combine
import ServiceManagement

@MainActor
final class LoginItem: ObservableObject {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but the user has to allow it in System Settings.
        case needsApproval
        case unavailable(String)
    }

    @Published private(set) var state: State = .disabled
    @Published private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: state = .enabled
        case .requiresApproval: state = .needsApproval
        case .notRegistered: state = .disabled
        // Also reported for apps that were never registered, so only a
        // failed register() (below) is treated as a problem.
        case .notFound: state = .disabled
        @unknown default: state = .disabled
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = enabled
                ? "Couldn't add MouseForge to Login Items (\(error.localizedDescription)). Moving the app to the Applications folder usually fixes this."
                : error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
