//
//  GeneralScreen.swift
//  MouseForge
//
//  Global options: launch at login, remapping on/off, click timing, the
//  left/right click safety lock, and settings backup / restore / reset.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralScreen: View {
    @ObservedObject var state: AppState
    @ObservedObject var store: SettingsStore
    @ObservedObject var loginItem: LoginItem
    @State private var confirmUnlock = false
    @State private var confirmImport: URL?
    @State private var confirmReset = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open MouseForge at login", isOn: Binding(
                    get: { loginItem.state == .enabled || loginItem.state == .needsApproval },
                    set: { loginItem.setEnabled($0) }
                ))
                switch loginItem.state {
                case .needsApproval:
                    HStack {
                        Label("Allow MouseForge in System Settings ▸ Login Items.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") { loginItem.openSystemSettings() }
                    }
                case .unavailable(let reason):
                    Text(reason).foregroundStyle(.orange)
                case .enabled, .disabled:
                    EmptyView()
                }
                if let error = loginItem.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Remapping") {
                Toggle("Enable remapping", isOn: $state.isEnabled)
                LabeledContent("Kill switch") {
                    Text("⌃⌥⌘M turns all remapping off or on instantly, from any app.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TimingSlider(
                    title: "Double-click speed",
                    value: $store.settings.general.doubleClickInterval,
                    range: GeneralSettings.doubleClickRange
                )
                TimingSlider(
                    title: "Hold delay",
                    value: $store.settings.general.holdThreshold,
                    range: GeneralSettings.holdRange
                )
            } header: {
                Text("Timing")
            } footer: {
                Text("Double-click speed is how long MouseForge waits for another click, only on buttons that have a Double or Triple Click action. Buttons without one fire immediately.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Allow remapping left and right click", isOn: Binding(
                    get: { store.settings.general.allowPrimaryButtonRemap },
                    set: { newValue in
                        if newValue { confirmUnlock = true } else { store.settings.general.allowPrimaryButtonRemap = false }
                    }
                ))
            } header: {
                Text("Safety")
            } footer: {
                Text("Off by default so a wrong setting can't take away your ability to click.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Location") {
                    Text(store.fileURL.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                HStack {
                    Button("Export Backup…", action: exportBackup)
                    Button("Restore from Backup…", action: chooseBackup)
                    Spacer()
                    Button("Show in Finder") { store.revealInFinder() }
                }
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Settings & Backup")
            } footer: {
                Text("A backup contains every profile, ring, gesture, Smart Action, and option. Restoring or resetting first saves your current settings next to the settings file.")
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Button("Show Welcome & Permissions…") { WindowManager.shared.showOnboarding() }
            }
        }
        .formStyle(.grouped)
        .onAppear { DispatchQueue.main.async { loginItem.refresh() } }
        .unlockPrimaryButtonsAlert(isPresented: $confirmUnlock, store: store)
        .alert("Replace all settings with this backup?", isPresented: Binding(
            get: { confirmImport != nil }, set: { if !$0 { confirmImport = nil } }
        )) {
            Button("Restore", role: .destructive) {
                if let url = confirmImport { restore(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current settings are saved as a safety copy first.")
        }
        .alert("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                do {
                    try store.resetAll()
                    message = "Settings reset. A safety copy was saved."
                } catch {
                    message = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every profile, ring, gesture, and Smart Action goes back to the defaults. A safety copy is saved first.")
        }
    }
}

private struct TimingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: 0.05)
                    .frame(minWidth: 200)
                Text(String(format: "%.2f s", value))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

extension View {
    /// Confirmation before unlocking left/right click remapping.
    func unlockPrimaryButtonsAlert(isPresented: Binding<Bool>, store: SettingsStore) -> some View {
        alert("Allow remapping left and right click?", isPresented: isPresented) {
            Button("Allow", role: .destructive) { store.settings.general.allowPrimaryButtonRemap = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If you remap your main buttons and can't click anymore, press ⌃⌥⌘M to turn all remapping off.")
        }
    }
}

extension GeneralScreen {
    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let date = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "MouseForge Backup \(date).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            message = "Saved \(url.lastPathComponent)."
        } catch {
            message = error.localizedDescription
        }
    }

    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        confirmImport = url
    }

    private func restore(_ url: URL) {
        do {
            try store.importSettings(from: url)
            message = "Restored from \(url.lastPathComponent)."
        } catch {
            message = error.localizedDescription
        }
    }
}
