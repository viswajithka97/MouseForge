//
//  AppProfilesScreen.swift
//  MouseForge
//
//  Lists every app profile with how many settings it overrides, and lets
//  the user add or remove profiles.
//

import SwiftUI

struct AppProfilesScreen: View {
    @ObservedObject var store: SettingsStore
    /// The profile in use right now (frontmost app), if any.
    let activeBundleID: String?
    let edit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Profiles").font(.title2.bold())
                    Text("When an app with a profile is in front, MouseForge uses its settings. Anything a profile doesn't set comes from All Applications.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                AddAppMenu(store: store, label: "Add App") { edit($0) }
            }

            if store.settings.appProfiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No app profiles yet. Add an app to give it its own button settings.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.settings.appProfiles) { app in
                        row(for: app)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            suggestedPresets
        }
        .padding(24)
    }

    private var suggestedPresets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Presets").font(.headline)
            Text("One click creates a profile with sensible buttons and an Actions Ring for the app. You can change anything afterwards.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AppPresetCatalog.all, id: \.name) { preset in
                        PresetCard(preset: preset, applied: store.isPresetApplied(preset)) {
                            edit(store.applyPreset(preset))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func row(for app: AppProfile) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: AppPicker.icon(for: app))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.headline)
                    if app.bundleID == activeBundleID {
                        Text("Active")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                    }
                }
                Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            let count = app.profile.bindings.count
            Text(count == 1 ? "1 override" : "\(count) overrides")
                .foregroundStyle(.secondary)
            Button("Edit") { edit(app.bundleID) }
            Button(role: .destructive) {
                store.removeAppProfile(bundleID: app.bundleID)
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove \(app.name) profile")
        }
        .padding(.vertical, 4)
    }
}

private struct PresetCard: View {
    let preset: AppPreset
    let applied: Bool
    let apply: () -> Void

    private var appURL: URL? {
        preset.bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let url = appURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)
            Text(preset.name).font(.caption.weight(.semibold)).lineLimit(1)
            Text(appURL == nil ? "Not installed" : "\(preset.bindings.count) buttons + ring")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(applied ? "Applied" : "Apply", action: apply)
                .controlSize(.small)
                .disabled(applied)
        }
        .frame(width: 118, height: 128)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}
