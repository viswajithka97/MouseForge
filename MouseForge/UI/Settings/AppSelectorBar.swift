//
//  AppSelectorBar.swift
//  MouseForge
//
//  The strip at the top of per-app screens: "All Applications", one chip
//  per app profile (with the app's icon), and a "+" to add an app.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppSelectorBar: View {
    @ObservedObject var store: SettingsStore
    @Binding var selectedApp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    AppChip(
                        title: "All Applications",
                        icon: Image(systemName: "globe"),
                        isSelected: selectedApp == nil
                    ) { selectedApp = nil }

                    ForEach(store.settings.appProfiles) { app in
                        AppChip(
                            title: app.name,
                            icon: Image(nsImage: AppPicker.icon(for: app)),
                            isSelected: selectedApp == app.bundleID
                        ) { selectedApp = app.bundleID }
                        .contextMenu {
                            Button("Remove \(app.name) Profile", role: .destructive) {
                                store.removeAppProfile(bundleID: app.bundleID)
                            }
                        }
                    }

                    AddAppMenu(store: store) { added in selectedApp = added }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }

    private var caption: String {
        guard let selectedApp, let app = store.settings.appProfile(for: selectedApp) else {
            return "Settings for every app. App profiles can override any of them."
        }
        return "Only affects \(app.name). Anything you don't change here uses the All Applications setting."
    }
}

private struct AppChip: View {
    let title: String
    let icon: Image
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                Text(title).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "+" menu: running apps first, then a file picker for anything else.
struct AddAppMenu: View {
    @ObservedObject var store: SettingsStore
    var label: String? = nil
    let onAdd: (String) -> Void

    var body: some View {
        Menu {
            let existing = Set(store.settings.appProfiles.map(\.bundleID))
            let running = AppPicker.runningApps(excluding: existing)
            if !running.isEmpty {
                Section("Running Apps") {
                    ForEach(running, id: \.bundleID) { app in
                        Button(app.name) { add(app) }
                    }
                }
            }
            Button("Choose Application…") {
                if let app = AppPicker.chooseApplication() { add(app) }
            }
        } label: {
            if let label {
                Label(label, systemImage: "plus")
            } else {
                Image(systemName: "plus")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Add an app profile")
    }

    private func add(_ app: AppPicker.AppInfo) {
        store.addAppProfile(bundleID: app.bundleID, name: app.name, appPath: app.path)
        onAdd(app.bundleID)
    }
}

@MainActor
enum AppPicker {
    struct AppInfo {
        var bundleID: String
        var name: String
        var path: String?
    }

    static func runningApps(excluding: Set<String>) -> [AppInfo] {
        let ownID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppInfo? in
                guard let id = app.bundleIdentifier, id != ownID, !excluding.contains(id) else { return nil }
                return AppInfo(bundleID: id, name: app.localizedName ?? id, path: app.bundleURL?.path)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func chooseApplication() -> AppInfo? {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.prompt = "Add Profile"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier
        else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return AppInfo(bundleID: id, name: name, path: url.path)
    }

    static func icon(for app: AppProfile) -> NSImage {
        if let path = app.appPath, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    /// For the action editor's "Choose…" buttons.
    static func choosePath(for parameter: ActionParameter) -> String? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        switch parameter {
        case .application:
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
        case .folder:
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        default:
            break
        }
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }
}
