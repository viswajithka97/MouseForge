//
//  SettingsView.swift
//  MouseForge
//
//  The Settings window: a sidebar of sections and, for per-app sections, an
//  app-selector bar on top.
//

import Combine
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case devices, buttons, actionsRing, gestures, smartActions, scrolling, pointer, logitech, appProfiles, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .devices: return "Devices"
        case .buttons: return "Buttons"
        case .actionsRing: return "Actions Ring"
        case .gestures: return "Gestures"
        case .smartActions: return "Smart Actions"
        case .scrolling: return "Scrolling"
        case .pointer: return "Pointer"
        case .logitech: return "Device (Logitech)"
        case .appProfiles: return "App Profiles"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .devices: return "computermouse"
        case .buttons: return "button.programmable"
        case .actionsRing: return "circle.circle"
        case .gestures: return "hand.draw"
        case .smartActions: return "wand.and.stars"
        case .scrolling: return "scroll"
        case .pointer: return "cursorarrow.motionlines"
        case .logitech: return "dot.radiowaves.left.and.right"
        case .appProfiles: return "square.stack.3d.up"
        case .general: return "gearshape"
        }
    }

    /// Sections whose settings can differ per app.
    var usesAppSelector: Bool {
        switch self {
        case .buttons, .actionsRing, .gestures, .scrolling: return true
        default: return false
        }
    }
}

/// Which section and app the Settings window shows; shared so other
/// windows (and the menu) can jump to a section.
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var section: SettingsSection? = .buttons
    /// nil = "All Applications".
    @Published var selectedApp: String?
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var navigation = SettingsNavigation.shared

    private var section: SettingsSection? {
        get { navigation.section }
        nonmutating set { navigation.section = newValue }
    }

    private var selectedApp: String? {
        get { navigation.selectedApp }
        nonmutating set { navigation.selectedApp = newValue }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $navigation.section) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            let section = section ?? .buttons
            VStack(spacing: 0) {
                if section.usesAppSelector {
                    AppSelectorBar(store: state.store, selectedApp: $navigation.selectedApp)
                    Divider()
                }
                detail(for: section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(section.title)
        }
        .frame(minWidth: 940, minHeight: 620)
        .onChange(of: state.store.settings.appProfiles.map(\.bundleID)) { ids in
            if let selectedApp, !ids.contains(selectedApp) { self.selectedApp = nil }
        }
    }

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        switch section {
        case .buttons:
            ButtonsScreen(store: state.store, devices: state.devices, bundleID: selectedApp, buttons: state.configurableButtons) {
                self.section = .scrolling
            }
        case .appProfiles:
            AppProfilesScreen(store: state.store, activeBundleID: state.profiles.activeBundleID) { bundleID in
                selectedApp = bundleID
                self.section = .buttons
            }
        case .general:
            GeneralScreen(state: state, store: state.store, loginItem: state.loginItem)
        case .actionsRing:
            ActionsRingScreen(store: state.store, bundleID: selectedApp)
        case .gestures:
            GesturesScreen(store: state.store, bundleID: selectedApp, buttons: state.configurableButtons)
        case .smartActions:
            SmartActionsScreen(store: state.store)
        case .scrolling:
            ScrollingScreen(store: state.store, bundleID: selectedApp)
        case .pointer:
            PointerScreen(store: state.store, pointer: state.pointer, devices: state.devices)
        case .devices:
            DevicesScreen(devices: state.devices, permissions: state.permissions) {
                self.section = .logitech
            }
        case .logitech:
            LogitechScreen(devices: state.devices, store: state.store)
        }
    }
}
